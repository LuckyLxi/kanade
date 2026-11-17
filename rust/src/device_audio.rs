//! Windows 听歌识曲录电脑正在播放的声音。Win10 2004 起用进程回环排除 Kanade 自己，
//! 更早的系统退回默认输出设备回环（会混进 Kanade 的声音，识曲时它已暂停）。
//! 统一让系统转换成 [`SAMPLE_RATE`] Hz、[`CHANNELS`] 声道、16 位小端 PCM。

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::mpsc;
use std::time::Duration;

use anyhow::{anyhow, Context, Result};
use windows::core::{implement, IUnknown, Interface, Ref, HRESULT};
use windows::Win32::Foundation::{CloseHandle, HANDLE};
use windows::Win32::Media::Audio::*;
use windows::Win32::System::Com::StructuredStorage::PROPVARIANT;
use windows::Win32::System::Com::{
    CoCreateInstance, CoInitializeEx, CoUninitialize, BLOB, CLSCTX_ALL, COINIT_MULTITHREADED,
};
use windows::Win32::System::Threading::{CreateEventW, WaitForSingleObject};
use windows::Win32::System::Variant::VT_BLOB;

pub const SAMPLE_RATE: u32 = 44100;
pub const CHANNELS: u16 = 2;

/// 每次开始录音加一；录音线程发现代数变了就退出。
static GENERATION: AtomicU64 = AtomicU64::new(0);

/// 开始录音，`on_data` 返回 false 时停止。等录音真正开始或失败后才返回。
pub fn start(on_data: impl FnMut(Vec<u8>) -> bool + Send + 'static) -> Result<()> {
    let generation = GENERATION.fetch_add(1, Ordering::SeqCst) + 1;
    let (ready_tx, ready_rx) = mpsc::channel();
    std::thread::spawn(move || {
        if let Err(e) = unsafe { capture(generation, &ready_tx, on_data) } {
            let _ = ready_tx.send(Err(e));
        }
    });
    ready_rx
        .recv()
        .map_err(|_| anyhow!("loopback capture thread exited"))?
}

pub fn stop() {
    GENERATION.fetch_add(1, Ordering::SeqCst);
}

struct Com;

impl Drop for Com {
    fn drop(&mut self) {
        unsafe { CoUninitialize() }
    }
}

struct Event(HANDLE);

impl Drop for Event {
    fn drop(&mut self) {
        unsafe {
            let _ = CloseHandle(self.0);
        }
    }
}

unsafe fn capture(
    generation: u64,
    ready: &mpsc::Sender<Result<()>>,
    mut on_data: impl FnMut(Vec<u8>) -> bool,
) -> Result<()> {
    CoInitializeEx(None, COINIT_MULTITHREADED).ok()?;
    let _com = Com;
    let client = match process_loopback_client() {
        Ok(client) => client,
        Err(_) => default_loopback_client().context("activate loopback client")?,
    };
    let block = CHANNELS as u32 * 2;
    let format = WAVEFORMATEX {
        wFormatTag: WAVE_FORMAT_PCM as u16,
        nChannels: CHANNELS,
        nSamplesPerSec: SAMPLE_RATE,
        nAvgBytesPerSec: SAMPLE_RATE * block,
        nBlockAlign: block as u16,
        wBitsPerSample: 16,
        cbSize: 0,
    };
    client.Initialize(
        AUDCLNT_SHAREMODE_SHARED,
        AUDCLNT_STREAMFLAGS_LOOPBACK
            | AUDCLNT_STREAMFLAGS_EVENTCALLBACK
            | AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM
            | AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY,
        2_000_000, // 200 ms，单位 100 ns
        0,
        &format,
        None,
    )?;
    let event = Event(CreateEventW(None, false, false, None)?);
    client.SetEventHandle(event.0)?;
    let capture: IAudioCaptureClient = client.GetService()?;
    client.Start()?;
    let _ = ready.send(Ok(()));
    while GENERATION.load(Ordering::SeqCst) == generation {
        // 没有声音时系统不发事件，超时也照样检查是否该停
        WaitForSingleObject(event.0, 100);
        while capture.GetNextPacketSize()? > 0 {
            let mut data = std::ptr::null_mut();
            let mut frames = 0;
            let mut flags = 0;
            capture.GetBuffer(&mut data, &mut frames, &mut flags, None, None)?;
            let len = (frames * block) as usize;
            let pcm = if flags & AUDCLNT_BUFFERFLAGS_SILENT.0 as u32 != 0 {
                vec![0; len]
            } else {
                std::slice::from_raw_parts(data, len).to_vec()
            };
            capture.ReleaseBuffer(frames)?;
            if !on_data(pcm) {
                stop();
                break;
            }
        }
    }
    let _ = client.Stop();
    Ok(())
}

#[implement(IActivateAudioInterfaceCompletionHandler)]
struct Activated(mpsc::Sender<()>);

impl IActivateAudioInterfaceCompletionHandler_Impl for Activated_Impl {
    fn ActivateCompleted(
        &self,
        _operation: Ref<IActivateAudioInterfaceAsyncOperation>,
    ) -> windows::core::Result<()> {
        let _ = self.0.send(());
        Ok(())
    }
}

/// 录除 Kanade 进程树以外的所有声音；Win10 2004 之前没有这个虚拟设备，激活会失败。
unsafe fn process_loopback_client() -> Result<IAudioClient> {
    let mut params = AUDIOCLIENT_ACTIVATION_PARAMS {
        ActivationType: AUDIOCLIENT_ACTIVATION_TYPE_PROCESS_LOOPBACK,
        Anonymous: AUDIOCLIENT_ACTIVATION_PARAMS_0 {
            ProcessLoopbackParams: AUDIOCLIENT_PROCESS_LOOPBACK_PARAMS {
                TargetProcessId: std::process::id(),
                ProcessLoopbackMode: PROCESS_LOOPBACK_MODE_EXCLUDE_TARGET_PROCESS_TREE,
            },
        },
    };
    // blob 指向栈上的 params，不能让 Drop 的 PropVariantClear 去释放它
    let mut prop = std::mem::ManuallyDrop::new(PROPVARIANT::default());
    let inner = &mut *prop.Anonymous.Anonymous;
    inner.vt = VT_BLOB;
    inner.Anonymous.blob = BLOB {
        cbSize: std::mem::size_of::<AUDIOCLIENT_ACTIVATION_PARAMS>() as u32,
        pBlobData: &mut params as *mut _ as *mut u8,
    };
    let (tx, rx) = mpsc::channel();
    let handler: IActivateAudioInterfaceCompletionHandler = Activated(tx).into();
    let operation = ActivateAudioInterfaceAsync(
        VIRTUAL_AUDIO_DEVICE_PROCESS_LOOPBACK,
        &IAudioClient::IID,
        Some(&*prop),
        &handler,
    )?;
    rx.recv_timeout(Duration::from_secs(5))?;
    let mut result = HRESULT(0);
    let mut client: Option<IUnknown> = None;
    operation.GetActivateResult(&mut result, &mut client)?;
    result.ok()?;
    Ok(client.context("no audio client")?.cast()?)
}

unsafe fn default_loopback_client() -> Result<IAudioClient> {
    let enumerator: IMMDeviceEnumerator = CoCreateInstance(&MMDeviceEnumerator, None, CLSCTX_ALL)?;
    let device = enumerator.GetDefaultAudioEndpoint(eRender, eConsole)?;
    Ok(device.Activate(CLSCTX_ALL, None)?)
}

#[cfg(test)]
mod tests {
    use std::sync::atomic::AtomicUsize;
    use std::sync::Arc;

    /// 真机录 2 秒；电脑在放声音时字节数应接近 2 × 44100 × 4。
    #[test]
    #[ignore]
    fn captures_device_audio() {
        let bytes = Arc::new(AtomicUsize::new(0));
        let counter = bytes.clone();
        super::start(move |pcm| {
            counter.fetch_add(pcm.len(), super::Ordering::SeqCst);
            true
        })
        .unwrap();
        std::thread::sleep(std::time::Duration::from_secs(2));
        super::stop();
        println!("captured {} bytes", bytes.load(super::Ordering::SeqCst));
    }
}
