/*
    Project: OpenMidiSesh
    File: midi_bridge.c
    Purpose: Bridge the FreeBASIC endpoint adapter to Android's MIDI service.
    Responsibilities: JNI thread attachment, bounded copies and exception checks.
    This file does not parse MIDI or access the editor. Included in the staged
    NativeActivity translation unit, without changing the installed toolchain.
    The mutex protects the global JNI reference against activity recreation.
*/
#include <jni.h>
#include <pthread.h>
#include <time.h>

static JavaVM *ose_midi_vm;
static jobject ose_midi_bridge;
static pthread_mutex_t ose_midi_mutex = PTHREAD_MUTEX_INITIALIZER;

JNIEXPORT void JNICALL Java_org_freebasic_android_OpenMidiBridge_nativeAttach(
    JNIEnv *env, jclass type, jobject bridge)
{
    (void)type;
    pthread_mutex_lock(&ose_midi_mutex);
    (*env)->GetJavaVM(env, &ose_midi_vm);
    if (ose_midi_bridge) (*env)->DeleteGlobalRef(env, ose_midi_bridge);
    ose_midi_bridge = (*env)->NewGlobalRef(env, bridge);
    pthread_mutex_unlock(&ose_midi_mutex);
}

/* All calls originate on the editor thread. Detach only attachments we own. */
static JNIEnv *ose_midi_env(int *attached)
{
    JNIEnv *env = NULL;
    *attached = 0;
    if (!ose_midi_vm || !ose_midi_bridge) return NULL;
    if ((*ose_midi_vm)->GetEnv(ose_midi_vm, (void **)&env, JNI_VERSION_1_6) != JNI_OK) {
        if ((*ose_midi_vm)->AttachCurrentThread(ose_midi_vm, &env, NULL) != JNI_OK) return NULL;
        *attached = 1;
    }
    return env;
}

int ose_midi_call(const char *method, int argument, int has_argument)
{
    int attached, result = 0;
    pthread_mutex_lock(&ose_midi_mutex);
    JNIEnv *env = ose_midi_env(&attached);
    if (env) {
        jclass type = (*env)->GetObjectClass(env, ose_midi_bridge);
        jmethodID id = (*env)->GetMethodID(env, type, method, has_argument ? "(I)I" : "()I");
        if (id) result = has_argument ? (*env)->CallIntMethod(env, ose_midi_bridge, id, argument) :
            (*env)->CallIntMethod(env, ose_midi_bridge, id);
        if ((*env)->ExceptionCheck(env)) { (*env)->ExceptionClear(env); result = 0; }
        (*env)->DeleteLocalRef(env, type);
        if (attached) (*ose_midi_vm)->DetachCurrentThread(ose_midi_vm);
    }
    pthread_mutex_unlock(&ose_midi_mutex);
    return result;
}

int ose_midi_read(unsigned char *target)
{
    int attached, size = 0;
    if (!target) return 0;
    pthread_mutex_lock(&ose_midi_mutex);
    JNIEnv *env = ose_midi_env(&attached);
    if (env) {
        jclass type = (*env)->GetObjectClass(env, ose_midi_bridge);
        jmethodID id = (*env)->GetMethodID(env, type, "read", "([B)I");
        jbyteArray bytes = (*env)->NewByteArray(env, 260);
        if (id && bytes) {
            size = (*env)->CallIntMethod(env, ose_midi_bridge, id, bytes);
            if (size >= 5 && size <= 260) (*env)->GetByteArrayRegion(env, bytes, 0, size, (jbyte *)target);
            else size = 0;
        }
        if ((*env)->ExceptionCheck(env)) { (*env)->ExceptionClear(env); size = 0; }
        if (bytes) (*env)->DeleteLocalRef(env, bytes);
        (*env)->DeleteLocalRef(env, type);
        if (attached) (*ose_midi_vm)->DetachCurrentThread(ose_midi_vm);
    }
    pthread_mutex_unlock(&ose_midi_mutex);
    return size;
}

void ose_midi_name(int index, char *target, int capacity)
{
    int attached;
    if (!target || capacity < 1) return;
    target[0] = 0;
    pthread_mutex_lock(&ose_midi_mutex);
    JNIEnv *env = ose_midi_env(&attached);
    if (env) {
        jclass type = (*env)->GetObjectClass(env, ose_midi_bridge);
        jmethodID id = (*env)->GetMethodID(env, type, "name", "(I)Ljava/lang/String;");
        jstring label = id ? (jstring)(*env)->CallObjectMethod(env, ose_midi_bridge, id, index) : NULL;
        if (label && !(*env)->ExceptionCheck(env)) {
            const char *utf = (*env)->GetStringUTFChars(env, label, NULL);
            if (utf) { snprintf(target, (size_t)capacity, "%s", utf); (*env)->ReleaseStringUTFChars(env, label, utf); }
        }
        if ((*env)->ExceptionCheck(env)) { (*env)->ExceptionClear(env); target[0] = 0; }
        if (label) (*env)->DeleteLocalRef(env, label);
        (*env)->DeleteLocalRef(env, type);
        if (attached) (*ose_midi_vm)->DetachCurrentThread(ose_midi_vm);
    }
    pthread_mutex_unlock(&ose_midi_mutex);
}

unsigned int ose_midi_clock(void)
{
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) return 0;
    return (unsigned int)((uint64_t)now.tv_sec * 1000 + now.tv_nsec / 1000000);
}
/* end of midi_bridge.c */
