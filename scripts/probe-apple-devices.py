#!/usr/bin/env python3
"""Reads the battery of iPhones and iPads this Mac trusts, the way Finder reaches them.

Read-only. Talks to usbmuxd (/var/run/usbmuxd, open to the logged-in user), opens a lockdown
session with the pairing record macOS made when "Trust This Computer" was tapped on the
device, and asks for the com.apple.mobile.battery domain. It never pairs, never changes
anything on the device and needs no root or extra permission. A device shows up when it is
connected by cable, or on the same Wi-Fi with "Show this iPhone when on Wi-Fi" on in Finder.

Usage: python3 -I scripts/probe-apple-devices.py
See docs/apple-device-batteries.md.
"""
import os
import plistlib
import socket
import ssl
import struct
import tempfile

LOCKDOWN_PORT = 62078


def usbmuxd():
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect("/var/run/usbmuxd")
    return s


def receive_exactly(sock, count):
    data = b""
    while len(data) < count:
        chunk = sock.recv(count - len(data))
        if not chunk:
            raise ConnectionError("connection closed")
        data += chunk
    return data


def mux_request(sock, message):
    """One usbmuxd plist message: a 16-byte header (length, version 1, type 8 = plist, tag)."""
    body = plistlib.dumps(dict(message, ClientVersionString="isle8-probe", ProgName="isle8-probe"))
    sock.sendall(struct.pack("<IIII", 16 + len(body), 1, 8, 1) + body)
    length = struct.unpack("<I", receive_exactly(sock, 16)[:4])[0]
    return plistlib.loads(receive_exactly(sock, length - 16))


def lockdown_request(sock, message):
    """Lockdown messages are a 4-byte big-endian length and an XML plist."""
    body = plistlib.dumps(dict(message, Label="isle8-probe"))
    sock.sendall(struct.pack(">I", len(body)) + body)
    length = struct.unpack(">I", receive_exactly(sock, 4))[0]
    return plistlib.loads(receive_exactly(sock, length))


def battery(device):
    properties = device["Properties"]
    udid = properties.get("SerialNumber", "")
    record = mux_request(usbmuxd(), {"MessageType": "ReadPairRecord", "PairRecordID": udid})
    if "PairRecordData" not in record:
        return "not trusted by this Mac (connect it by cable once and tap Trust)"
    pairing = plistlib.loads(record["PairRecordData"])

    sock = usbmuxd()
    # usbmuxd wants the port in network byte order.
    port = ((LOCKDOWN_PORT & 0xFF) << 8) | (LOCKDOWN_PORT >> 8)
    result = mux_request(sock, {"MessageType": "Connect", "DeviceID": device["DeviceID"], "PortNumber": port})
    if result.get("Number", 1) != 0:
        return f"could not connect (usbmuxd result {result.get('Number')})"

    name = lockdown_request(sock, {"Request": "GetValue", "Key": "DeviceName"}).get("Value", "?")
    session = lockdown_request(sock, {
        "Request": "StartSession",
        "HostID": pairing["HostID"],
        "SystemBUID": pairing["SystemBUID"],
    })
    if "Error" in session:
        return f"{name}: session refused ({session['Error']})"

    if session.get("EnableSessionSSL"):
        # The host certificate and key from the pairing record identify this Mac. They are
        # written to a private temporary folder only for the handshake.
        with tempfile.TemporaryDirectory() as folder:
            os.chmod(folder, 0o700)
            certificate = os.path.join(folder, "host.pem")
            with open(certificate, "wb") as file:
                file.write(pairing["HostCertificate"] + b"\n" + pairing["HostPrivateKey"])
            context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
            context.check_hostname = False
            context.verify_mode = ssl.CERT_NONE
            try:
                context.set_ciphers("ALL:!aNULL:!eNULL:@SECLEVEL=0")
            except ssl.SSLError:
                pass
            context.load_cert_chain(certificate)
            sock = context.wrap_socket(sock)

    values = lockdown_request(sock, {"Request": "GetValue", "Domain": "com.apple.mobile.battery"}).get("Value", {})
    lockdown_request(sock, {"Request": "StopSession", "SessionID": session.get("SessionID", "")})
    level = values.get("BatteryCurrentCapacity")
    charging = " (charging)" if values.get("BatteryIsCharging") else ""
    return f"{name}: {level}%{charging}" if level is not None else f"{name}: no battery value ({sorted(values)})"


def main():
    devices = mux_request(usbmuxd(), {"MessageType": "ListDevices"}).get("DeviceList", [])
    if not devices:
        print("No iPhone or iPad visible to usbmuxd. Connect one by cable, or turn on")
        print("\"Show this iPhone when on Wi-Fi\" in Finder and keep both on the same network.")
        return
    for device in devices:
        kind = device["Properties"].get("ConnectionType", "?")
        try:
            print(f"[{kind}] {battery(device)}")
        except Exception as error:  # A probe: report and go on to the next device.
            print(f"[{kind}] failed: {error}")


if __name__ == "__main__":
    main()
