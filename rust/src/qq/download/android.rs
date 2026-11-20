//! Android 上经 MediaStore 存进系统「音乐/Kanade」（MediaStoreBridge.kt），文件记的是 content:// 地址。

use std::path::{Path, PathBuf};
use std::sync::OnceLock;

use anyhow::{bail, Context, Result};
use jni::objects::{GlobalRef, JClass, JObject, JString, JValue};
use jni::{JNIEnv, JavaVM};

static BRIDGE: OnceLock<(JavaVM, GlobalRef)> = OnceLock::new();

/// `MediaStoreBridge.install` 在每个进程的 `Application.onCreate` 里调用；
/// 后台线程找不到 App 的类，所以这里先存一份类引用。
#[no_mangle]
pub extern "system" fn Java_com_lxi_kanade_MediaStoreBridge_nativeInit(
    env: JNIEnv,
    class: JClass,
) {
    if let (Ok(vm), Ok(class)) = (env.get_java_vm(), env.new_global_ref(class)) {
        let _ = BRIDGE.set((vm, class));
    }
}

fn call<T>(
    f: impl for<'a> FnOnce(&mut JNIEnv<'a>, &JClass<'a>) -> jni::errors::Result<T>,
) -> Result<T> {
    let (vm, class) = BRIDGE.get().context("MediaStore bridge unavailable")?;
    let mut env = vm.attach_current_thread()?;
    let class: &JClass = class.as_obj().into();
    let result = f(&mut env, class);
    if env.exception_check().unwrap_or(false) {
        let ex = env.exception_occurred()?;
        env.exception_clear()?;
        let message = env
            .call_method(&ex, "toString", "()Ljava/lang/String;", &[])
            .and_then(|v| v.l())
            .and_then(|o| env.get_string(&JString::from(o)).map(String::from))
            .unwrap_or_default();
        bail!(std::io::Error::new(
            if message.contains("SecurityException") {
                std::io::ErrorKind::PermissionDenied
            } else {
                std::io::ErrorKind::Other
            },
            message,
        ));
    }
    Ok(result?)
}

fn string(env: &mut JNIEnv, value: JObject) -> jni::errors::Result<String> {
    Ok(env.get_string(&JString::from(value))?.into())
}

pub fn default_dir() -> PathBuf {
    PathBuf::from("Music/Kanade")
}

pub fn save(src: &Path, name: &str, mime: &str, _overwrite: bool) -> Result<String> {
    call(|env, class| {
        let src = env.new_string(src.to_string_lossy())?;
        let name = env.new_string(name)?;
        let mime = env.new_string(mime)?;
        let uri = env
            .call_static_method(
                class,
                "save",
                "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;",
                &[JValue::Object(&src), JValue::Object(&name), JValue::Object(&mime)],
            )?
            .l()?;
        string(env, uri)
    })
}

pub fn lrc_name(_file: &str, stem: &str) -> String {
    format!("{stem}.lrc")
}

pub fn delete(file: &str) {
    let _ = call(|env, class| {
        let file = env.new_string(file)?;
        env.call_static_method(
            class,
            "delete",
            "(Ljava/lang/String;)V",
            &[JValue::Object(&file)],
        )?;
        Ok(())
    });
}

#[no_mangle]
pub extern "system" fn Java_com_lxi_kanade_MediaStoreBridge_nativeNetworkChanged(
    _env: JNIEnv,
    _class: JClass,
    metered: jni::sys::jboolean,
) {
    super::set_metered(metered != 0);
}

/// [total] 为 0 时收起通知、停掉前台服务。
pub fn notify(done: u32, total: u32) {
    let _ = call(|env, class| {
        env.call_static_method(
            class,
            "notifyDownloads",
            "(II)V",
            &[JValue::Int(done as i32), JValue::Int(total as i32)],
        )?;
        Ok(())
    });
}

pub fn exists(file: &str) -> bool {
    call(|env, class| {
        let file = env.new_string(file)?;
        env.call_static_method(
            class,
            "exists",
            "(Ljava/lang/String;)Z",
            &[JValue::Object(&file)],
        )?
        .z()
    })
    .unwrap_or(false)
}

/// 授权的文件夹里的文件，一行一个「地址\t文件名\t大小\tmedia:<id>」，最后一项可能为空。
/// 没授权文件夹时只列得出这次安装存的。
pub fn list() -> Result<Vec<super::Entry>> {
    let text = call(|env, class| {
        let v = env
            .call_static_method(class, "list", "()Ljava/lang/String;", &[])?
            .l()?;
        string(env, v)
    })?;
    Ok(text
        .lines()
        .filter_map(|line| {
            let mut parts = line.split('\t');
            Some(super::Entry {
                file: parts.next()?.to_owned(),
                name: parts.next()?.to_owned(),
                size: parts.next()?.parse().ok()?,
                alias: parts.next().filter(|a| !a.is_empty()).map(str::to_owned),
            })
        })
        .collect())
}

pub fn open(file: &str) -> Result<std::fs::File> {
    use std::os::fd::FromRawFd;
    let fd = call(|env, class| {
        let file = env.new_string(file)?;
        env.call_static_method(
            class,
            "openFd",
            "(Ljava/lang/String;)I",
            &[JValue::Object(&file)],
        )?
        .i()
    })?;
    if fd < 0 {
        bail!("cannot open {file}");
    }
    // Kotlin 那边 detachFd 交出了所有权，File 关掉时一起关
    Ok(unsafe { std::fs::File::from_raw_fd(fd) })
}
