/*
    Project: OpenMidiSesh
    File: OpenMidiBridge.java
    Purpose: Receive Android system MIDI byte streams, including USB devices.
    Responsibilities: Endpoint discovery, asynchronous opens and a bounded queue.
    This file does not contain MIDI parsing, synthesis or editor policy.

    Android names ports from the device's perspective: its OUTPUT is our input.
    All queue and lifecycle state is guarded by this object's monitor. Callbacks
    never enter FreeBASIC. A generation rejects late opens and stale receivers.
*/
package org.freebasic.android;

import android.content.Context;
import android.media.midi.*;
import android.os.Handler;
import android.os.Looper;
import java.io.IOException;
import java.util.ArrayList;

class OpenMidiBridge {
    private static OpenMidiBridge instance;
    private final MidiManager manager;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final ArrayList<MidiDeviceInfo> devices = new ArrayList<>();
    private final ArrayList<Integer> ports = new ArrayList<>();
    // 256 packets of at most 256 MIDI bytes, plus a 32-bit monotonic timestamp.
    private final byte[][] queue = new byte[256][260];
    private final int[] lengths = new int[256];
    private int head, count, generation, state, deviceId = -1;
    private int dropped;
    private MidiDevice device;
    private MidiOutputPort port;
    private MidiManager.DeviceCallback deviceCallback;
    private final Context context;

    private static native void nativeAttach(OpenMidiBridge bridge);

    static void initialize(Context context) {
        if (android.os.Build.VERSION.SDK_INT < 23) return;
        dispose();
        instance = new OpenMidiBridge(context.getApplicationContext());
        nativeAttach(instance);
    }

    static void shutdown() {
        if (instance != null) instance.close();
    }

    static void dispose() {
        if (instance == null) return;
        instance.close();
        if (instance.manager != null && instance.deviceCallback != null)
            instance.manager.unregisterDeviceCallback(instance.deviceCallback);
        instance = null;
    }

    private OpenMidiBridge(Context context) {
        this.context = context;
        manager = (MidiManager) context.getSystemService(Context.MIDI_SERVICE);
        deviceCallback = new MidiManager.DeviceCallback() {
            @Override public void onDeviceRemoved(MidiDeviceInfo info) {
                synchronized (OpenMidiBridge.this) {
                    if (deviceId == info.getId()) close();
                }
            }
        };
        if (manager != null) manager.registerDeviceCallback(deviceCallback, handler);
    }

    public synchronized int refresh() {
        devices.clear();
        ports.clear();
        if (manager == null) return 0;
        // The legacy query deliberately selects MIDI 1.0 byte-stream ports.
        // UMP / MIDI 2.0 packets require a separate decoder and are not bytes.
        for (MidiDeviceInfo info : manager.getDevices()) {
            for (MidiDeviceInfo.PortInfo p : info.getPorts()) {
                if (p.getType() == MidiDeviceInfo.PortInfo.TYPE_OUTPUT) {
                    devices.add(info);
                    ports.add(p.getPortNumber());
                }
            }
        }
        return devices.size();
    }

    public synchronized String name(int index) {
        if (index < 0 || index >= devices.size()) return "";
        MidiDeviceInfo info = devices.get(index);
        String label = info.getProperties().getString(MidiDeviceInfo.PROPERTY_NAME);
        return (label == null ? "MIDI device" : label) + " / " + (ports.get(index) + 1);
    }

    public synchronized int open(int index) {
        close();
        if (manager == null || index < 0 || index >= devices.size()) return 0;
        final int request = generation;
        final int portNumber = ports.get(index);
        deviceId = devices.get(index).getId();
        state = 1; // Opening is asynchronous; never block the editor thread.
        try {
            manager.openDevice(devices.get(index), new MidiManager.OnDeviceOpenedListener() {
                @Override public void onDeviceOpened(MidiDevice opened) {
                synchronized (OpenMidiBridge.this) {
                    if (request != generation || opened == null) {
                        if (opened != null) try { opened.close(); } catch (IOException ignored) { }
                        if (request == generation) state = 0;
                        return;
                    }
                    try {
                    device = opened;
                    port = opened.openOutputPort(portNumber);
                    if (port == null) { close(); return; }
                    port.connect(new MidiReceiver() {
                        @Override public void onSend(byte[] bytes, int offset, int length, long timestamp) {
                            synchronized (OpenMidiBridge.this) {
                                if (request != generation) return;
                                // System.nanoTime and Android MIDI timestamps share CLOCK_MONOTONIC.
                                long millis = (timestamp > 0 ? timestamp : System.nanoTime()) / 1000000L;
                                while (length > 0) {
                                    int size = Math.min(length, 256);
                                    if (count == queue.length) { dropped++; return; }
                                    int slot = (head + count) % queue.length;
                                    for (int i = 0; i < 4; i++) queue[slot][i] = (byte)(millis >> (8 * i));
                                    System.arraycopy(bytes, offset, queue[slot], 4, size);
                                    lengths[slot] = size + 4;
                                    count++;
                                    offset += size;
                                    length -= size;
                                }
                            }
                        }
                    });
                    state = 2;
                    } catch (RuntimeException error) { close(); }
                }
                }
            }, handler);
        } catch (RuntimeException error) { close(); return 0; }
        return 1;
    }

    public synchronized int status() { return state; }
    public int displayWidth() { return context.getResources().getDisplayMetrics().widthPixels; }
    public int displayHeight() { return context.getResources().getDisplayMetrics().heightPixels; }
    public int displayDpi() { return context.getResources().getDisplayMetrics().densityDpi; }
    public synchronized int drops() { return dropped; }
    public synchronized int clear() { head = count = 0; return 0; }

    public synchronized int read(byte[] target) {
        if (count == 0 || target.length < 260) return 0;
        int size = lengths[head];
        System.arraycopy(queue[head], 0, target, 0, size);
        head = (head + 1) % queue.length;
        count--;
        return size;
    }

    public synchronized int close() {
        generation++;
        state = 0;
        deviceId = -1;
        if (port != null) try { port.close(); } catch (IOException ignored) { }
        if (device != null) try { device.close(); } catch (IOException ignored) { }
        port = null;
        device = null;
        head = count = dropped = 0;
        return 0;
    }
}
/* end of OpenMidiBridge.java */
