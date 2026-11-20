#ifndef RUNNER_SOFTWARE_RENDERING_H_
#define RUNNER_SOFTWARE_RENDERING_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <memory>

// The "disable hardware acceleration" setting. It is read once before the
// engine is created, so a change applies on the next launch.
void ApplySoftwareRendering();

// kanade/rendering: "get" returns the saved setting, "set" saves a bool.
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
CreateSoftwareRenderingChannel(flutter::BinaryMessenger* messenger);

#endif  // RUNNER_SOFTWARE_RENDERING_H_
