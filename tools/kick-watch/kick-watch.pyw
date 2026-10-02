# -*- coding: utf-8 -*-
"""
kick-watch.pyw - GTA 방치 킥·세션 이탈의 원인을 나중에 가릴 수 있게 기록만 남기는 감시기.

작업 스케줄러 "GTA Kick Watch" 가 5분마다 pythonw 로 띄운다(창이 없어 포커스를 안 뺏는다). 이미 돌고 있으면 바로 끝난다.
게임 창과 매크로에는 키·클릭·포커스 변경을 보내지 않는다. 하는 일은 읽기(GetForegroundWindow, GetLastInputInfo,
launcher.log, gta-afk.log)와 화면 캡처뿐이다. Main.ahk 와 따로 돌아서 매크로를 다시 띄울 필요가 없다.

기록은 %USERPROFILE%\\gta-kick 에 둔다(AppData 는 Claude 앱 가상화 때문에 쓰지 않는다. gta-perf 와 같은 까닭).
  fg.log      전경 창이 바뀔 때마다 한 줄: 날짜 시각, 실행 파일, 창 제목. 누가 언제 GTA 포커스를 가져갔는지 본다.
  events.log  launcher.log 에 세션 변경(NotifyActiveSessionChange)이 찍힐 때마다 한 줄: 그 순간의 전경 창,
              마지막 입력부터 지난 초(주입 입력 포함), gta-afk.log 끝 3줄, 원격 데스크톱 접속 여부.
  shots\\      세션 변경 2초·15초·45초 뒤의 전체 화면 PNG. 튕긴 뒤 뜨는 알림 문구(방치·연결 끊김 등)가 여기 남는다.

2026-10-02: 19:45:50 킥은 원격 데스크톱이 13분 전경을 쥔 탓으로 로그가 맞았지만, 20:57:27 세션 변경은 AFK 입력이
정상으로 찍혔는데도 일어났고 그 순간의 화면이 없어 원인을 못 가렸다. 그 빈칸을 메우려고 만들었다.

시험: python kick-watch.pyw --once  (상태 한 줄과 캡처 한 장을 남기고 끝난다)
"""
import ctypes
import ctypes.wintypes as wt
import datetime
import os
import struct
import sys
import time
import zlib

user32 = ctypes.WinDLL("user32", use_last_error=True)
gdi32 = ctypes.WinDLL("gdi32", use_last_error=True)
kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
psapi = ctypes.WinDLL("psapi", use_last_error=True)

HOME = os.environ.get("USERPROFILE", os.path.expanduser("~"))
OUT = os.path.join(HOME, "gta-kick")
SHOTS = os.path.join(OUT, "shots")
LAUNCHER_LOG = os.path.join(HOME, "Documents", "Rockstar Games", "Launcher", "launcher.log")
AFK_LOG = os.path.join(HOME, "AppData", "Local", "Temp", "gta-afk.log")
GTA_EXE = "GTA5_Enhanced.exe"
SESSION_MARK = "NotifyActiveSessionChange"
SHOT_DELAYS = (2, 15, 45)
KEEP_SHOTS = 120
LOG_MAX = 2 * 1024 * 1024


def now():
    return datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def append(name, line):
    path = os.path.join(OUT, name)
    try:
        if os.path.exists(path) and os.path.getsize(path) > LOG_MAX:
            os.replace(path, path + ".1")
        with open(path, "a", encoding="utf-8") as f:
            f.write(now() + " " + line + "\n")
    except OSError:
        pass


class LASTINPUTINFO(ctypes.Structure):
    _fields_ = [("cbSize", wt.UINT), ("dwTime", wt.DWORD)]


def input_idle_sec():
    info = LASTINPUTINFO(ctypes.sizeof(LASTINPUTINFO), 0)
    if not user32.GetLastInputInfo(ctypes.byref(info)):
        return -1
    return ((kernel32.GetTickCount() - info.dwTime) & 0xFFFFFFFF) // 1000


def exe_of(pid):
    kernel32.OpenProcess.restype = wt.HANDLE
    h = kernel32.OpenProcess(0x1000, False, pid)  # PROCESS_QUERY_LIMITED_INFORMATION
    if not h:
        return "pid" + str(pid)
    try:
        buf = ctypes.create_unicode_buffer(520)
        size = wt.DWORD(520)
        if kernel32.QueryFullProcessImageNameW(wt.HANDLE(h), 0, buf, ctypes.byref(size)):
            return os.path.basename(buf.value)
        return "pid" + str(pid)
    finally:
        kernel32.CloseHandle(wt.HANDLE(h))


def foreground():
    user32.GetForegroundWindow.restype = wt.HWND
    hwnd = user32.GetForegroundWindow()
    if not hwnd:
        return ("(없음)", "")
    pid = wt.DWORD(0)
    user32.GetWindowThreadProcessId(wt.HWND(hwnd), ctypes.byref(pid))
    title = ctypes.create_unicode_buffer(200)
    user32.GetWindowTextW(wt.HWND(hwnd), title, 200)
    return (exe_of(pid.value), title.value.replace("\n", " ")[:80])


def process_names():
    names = set()
    arr = (wt.DWORD * 4096)()
    got = wt.DWORD(0)
    if psapi.EnumProcesses(ctypes.byref(arr), ctypes.sizeof(arr), ctypes.byref(got)):
        for i in range(got.value // ctypes.sizeof(wt.DWORD)):
            if arr[i]:
                names.add(exe_of(arr[i]).lower())
    return names


def tail_lines(path, count):
    try:
        with open(path, "rb") as f:
            f.seek(0, 2)
            size = f.tell()
            f.seek(max(0, size - 4096))
            text = f.read().decode("utf-8", "replace")
        return [l.strip() for l in text.splitlines() if l.strip()][-count:]
    except OSError:
        return []


class BITMAPINFOHEADER(ctypes.Structure):
    _fields_ = [("biSize", wt.DWORD), ("biWidth", wt.LONG), ("biHeight", wt.LONG), ("biPlanes", wt.WORD),
                ("biBitCount", wt.WORD), ("biCompression", wt.DWORD), ("biSizeImage", wt.DWORD),
                ("biXPelsPerMeter", wt.LONG), ("biYPelsPerMeter", wt.LONG), ("biClrUsed", wt.DWORD),
                ("biClrImportant", wt.DWORD)]


def screenshot(tag):
    """모든 모니터를 한 장으로 찍어 shots\\ 에 PNG 로 저장한다. 실패하면 빈 문자열."""
    for fn in (user32.GetDC, gdi32.CreateCompatibleDC):
        fn.restype = wt.HDC
    gdi32.CreateCompatibleBitmap.restype = wt.HBITMAP
    gdi32.SelectObject.restype = wt.HGDIOBJ
    x, y = user32.GetSystemMetrics(76), user32.GetSystemMetrics(77)
    w, h = user32.GetSystemMetrics(78), user32.GetSystemMetrics(79)
    if w <= 0 or h <= 0:
        return ""
    screen = user32.GetDC(None)
    mem = gdi32.CreateCompatibleDC(wt.HDC(screen))
    bmp = gdi32.CreateCompatibleBitmap(wt.HDC(screen), w, h)
    old = gdi32.SelectObject(wt.HDC(mem), wt.HGDIOBJ(bmp))
    try:
        if not gdi32.BitBlt(wt.HDC(mem), 0, 0, w, h, wt.HDC(screen), x, y, 0x00CC0020 | 0x40000000):
            return ""
        head = BITMAPINFOHEADER(ctypes.sizeof(BITMAPINFOHEADER), w, -h, 1, 32, 0, 0, 0, 0, 0, 0)
        raw = ctypes.create_string_buffer(w * h * 4)
        if not gdi32.GetDIBits(wt.HDC(mem), wt.HBITMAP(bmp), 0, h, raw, ctypes.byref(head), 0):
            return ""
    finally:
        gdi32.SelectObject(wt.HDC(mem), wt.HGDIOBJ(old))
        gdi32.DeleteObject(wt.HGDIOBJ(bmp))
        gdi32.DeleteDC(wt.HDC(mem))
        user32.ReleaseDC(None, wt.HDC(screen))
    bgra = raw.raw
    rgb = bytearray(w * h * 3)
    rgb[0::3], rgb[1::3], rgb[2::3] = bgra[2::4], bgra[1::4], bgra[0::4]
    row = w * 3
    data = b"".join(b"\x00" + bytes(rgb[i:i + row]) for i in range(0, len(rgb), row))

    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)

    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(data, 3)) + chunk(b"IEND", b""))
    name = datetime.datetime.now().strftime("%Y%m%d-%H%M%S") + "-" + tag + ".png"
    path = os.path.join(SHOTS, name)
    with open(path, "wb") as f:
        f.write(png)
    try:
        files = sorted(p for p in os.listdir(SHOTS) if p.endswith(".png"))
        for stale in files[:-KEEP_SHOTS]:
            os.remove(os.path.join(SHOTS, stale))
    except OSError:
        pass
    return name


def state_line():
    exe, title = foreground()
    procs = process_names()
    remote = "접속 중" if "remoting_desktop.exe" in procs else "없음"
    gta = "실행 중" if GTA_EXE.lower() in procs else "꺼짐"
    afk = " / ".join(tail_lines(AFK_LOG, 3)) or "(없음)"
    return (f"전경={exe} [{title}] | 마지막 입력 {input_idle_sec()}초 전(주입 포함) | GTA {gta} | "
            f"원격 데스크톱 {remote} | afk 로그 끝: {afk}")


def main():
    os.makedirs(SHOTS, exist_ok=True)
    try:
        user32.SetProcessDpiAwarenessContext(ctypes.c_void_p(-4))
    except Exception:
        pass

    if "--once" in sys.argv:
        shot = screenshot("test")
        append("events.log", "시험 실행 | " + state_line() + " | 캡처 " + (shot or "실패"))
        return

    kernel32.CreateMutexW.restype = wt.HANDLE
    mutex = kernel32.CreateMutexW(None, False, "Local\\gta-kick-watch")
    if not mutex or ctypes.get_last_error() == 183:  # ERROR_ALREADY_EXISTS
        return
    append("events.log", "감시 시작 pid " + str(os.getpid()))

    last_fg = None
    offset = None
    pending = []  # (찍을 시각, 꼬리표)
    while True:
        try:
            fg = foreground()
            if fg != last_fg:
                append("fg.log", f"{fg[0]} | {fg[1]}")
                last_fg = fg

            try:
                size = os.path.getsize(LAUNCHER_LOG)
            except OSError:
                size = None
            if size is not None:
                if offset is None or size < offset:  # 처음이거나 런처가 로그를 새로 만들었다
                    offset = size if offset is None else 0
                if size > offset:
                    with open(LAUNCHER_LOG, "rb") as f:
                        f.seek(offset)
                        fresh = f.read(size - offset).decode("utf-8", "replace")
                    offset = size
                    if SESSION_MARK in fresh:
                        stamp = datetime.datetime.now().strftime("%H%M%S")
                        append("events.log", "세션 변경 | " + state_line())
                        t = time.monotonic()
                        pending = [(t + d, f"session{stamp}-{d}s") for d in SHOT_DELAYS]

            due = [p for p in pending if p[0] <= time.monotonic()]
            if due:
                pending = [p for p in pending if p[0] > time.monotonic()]
                for _, tag in due:
                    shot = screenshot(tag)
                    append("events.log", "캡처 " + (shot or "실패") + " | " + state_line())
        except Exception as e:  # 감시기가 죽어 기록이 끊기는 쪽이 더 나쁘다
            append("events.log", "오류 " + repr(e)[:200])
        time.sleep(1)


if __name__ == "__main__":
    main()
