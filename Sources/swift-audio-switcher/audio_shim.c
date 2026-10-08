#include <CoreAudio/CoreAudio.h>
#include <CoreAudio/AudioHardware.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdlib.h>

// C shim for the deprecated CoreAudio C API.
// AudioObjectGetPropertyData (modern Swift API) returns an empty device list
// on macOS 14+. The deprecated C API still works. These functions are marked
// unavailable in Swift, so we call them from C.

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

int sas_get_all_devices(unsigned int **out_ids, unsigned int *out_count) {
    UInt32 size = 0;
    Boolean writable = false;
    OSStatus st = AudioHardwareGetPropertyInfo(kAudioHardwarePropertyDevices, &size, &writable);
    if (st != noErr) return (int)st;
    if (size == 0) { *out_ids = NULL; *out_count = 0; return 0; }
    AudioObjectID *ids = (AudioObjectID *)malloc(size);
    if (!ids) return -1;
    UInt32 sz = size;
    st = AudioHardwareGetProperty(kAudioHardwarePropertyDevices, &sz, ids);
    if (st != noErr) { free(ids); return (int)st; }
    *out_ids = (unsigned int *)ids;
    *out_count = sz / sizeof(AudioObjectID);
    return 0;
}

int sas_get_default_output(unsigned int *out_id) {
    UInt32 size = sizeof(AudioObjectID);
    return (int)AudioHardwareGetProperty(kAudioHardwarePropertyDefaultOutputDevice, &size, out_id);
}

int sas_set_default_output(unsigned int device_id) {
    AudioObjectID id = (AudioObjectID)device_id;
    UInt32 size = sizeof(AudioObjectID);
    return (int)AudioHardwareSetProperty(kAudioHardwarePropertyDefaultOutputDevice, size, &id);
}

int sas_get_device_name(unsigned int device_id, void **out_name) {
    UInt32 size = sizeof(CFStringRef);
    CFStringRef name = NULL;
    OSStatus st = AudioDeviceGetProperty((AudioDeviceID)device_id, 0, false,
                                          kAudioDevicePropertyDeviceNameCFString, &size, &name);
    if (st != noErr) return (int)st;
    *out_name = (void *)name;
    return 0;
}

int sas_get_device_uid(unsigned int device_id, void **out_uid) {
    UInt32 size = sizeof(CFStringRef);
    CFStringRef uid = NULL;
    OSStatus st = AudioDeviceGetProperty((AudioDeviceID)device_id, 0, false,
                                          kAudioDevicePropertyDeviceUID, &size, &uid);
    if (st != noErr) return (int)st;
    *out_uid = (void *)uid;
    return 0;
}

int sas_device_has_output(unsigned int device_id, int *out_has_output) {
    UInt32 size = 0;
    Boolean writable = false;
    OSStatus st = AudioDeviceGetPropertyInfo((AudioDeviceID)device_id, 0, false,
                                              kAudioDevicePropertyStreamConfiguration, &size, &writable);
    if (st != noErr) { *out_has_output = 0; return (int)st; }
    *out_has_output = (size > 0) ? 1 : 0;
    return 0;
}

int sas_device_can_be_default(unsigned int device_id, int *out_can_default) {
    UInt32 size = sizeof(UInt32);
    UInt32 val = 0;
    OSStatus st = AudioDeviceGetProperty((AudioDeviceID)device_id, 0, false,
                                          kAudioDevicePropertyDeviceCanBeDefaultDevice, &size, &val);
    if (st != noErr) { *out_can_default = 0; return (int)st; }
    *out_can_default = (val != 0) ? 1 : 0;
    return 0;
}

#pragma clang diagnostic pop
