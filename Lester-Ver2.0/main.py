import sys
import time
import pynput
import ctypes
import ctypes.wintypes
from threading import Thread
from hacks import casinofingerprint, casinokeypad, cayofingerprint, cayovoltage

def FindWindow(class_name, window_name):
    return ctypes.windll.user32.FindWindowW(class_name, window_name)

def GetWindowRect(hwnd):
    rect = ctypes.wintypes.RECT()
    ctypes.windll.user32.GetWindowRect(hwnd, ctypes.byref(rect))
    return (rect.left, rect.top, rect.right, rect.bottom)

def print_banner():
    print('''

██╗░░░░░███████╗░██████╗████████╗███████╗██████╗░  ██╗░░░██╗███████╗██████╗░  ██████╗░░░░░█████╗░
██║░░░░░██╔════╝██╔════╝╚══██╔══╝██╔════╝██╔══██╗  ██║░░░██║██╔════╝██╔══██╗  ╚════██╗░░░██╔══██╗
██║░░░░░█████╗░░╚█████╗░░░░██║░░░█████╗░░██████╔╝  ╚██╗░██╔╝█████╗░░██████╔╝  ░░███╔═╝░░░██║░░██║
██║░░░░░██╔══╝░░░╚═══██╗░░░██║░░░██╔══╝░░██╔══██╗  ░╚████╔╝░██╔══╝░░██╔══██╗  ██╔══╝░░░░░██║░░██║
███████╗███████╗██████╔╝░░░██║░░░███████╗██║░░██║  ░░╚██╔╝░░███████╗██║░░██║  ███████╗██╗╚█████╔╝
╚══════╝╚══════╝╚═════╝░░░░╚═╝░░░╚══════╝╚═╝░░╚═╝  ░░░╚═╝░░░╚══════╝╚═╝░░╚═╝  ╚══════╝╚═╝░╚════╝░
                                                                                          ''')

def print_credits():
    print('''
Made by JUSTDIE
Special thanks to RedHeadEmile
    ''')
    
def check_window():
    print('[*] Searching Grand Theft Auto V...')

    while True:
        hwnd = FindWindow(None, "Grand Theft Auto V")
        
        if hwnd:
            print('[*] Grand Theft Auto V Detected!')
            print('')
            print('=============================================')
            return GetWindowRect(hwnd)
        
        time.sleep(1)

def casino_fingerprint(bbox):
    thread = Thread(target=casinofingerprint.main, args=(bbox,))
    thread.start()

def casino_keypad(bbox):
    thread = Thread(target=casinokeypad.main, args=(bbox,))
    thread.start()

def cayo_fingerprint(bbox):
    thread = Thread(target=cayofingerprint.main, args=(bbox,))
    thread.start()

def cayo_voltage(bbox):
    thread = Thread(target=cayovoltage.main, args=(bbox,))
    thread.start()

def shutdown():
    sys.exit()

def main():
    print_banner()
    print_credits()

    bbox = check_window()
    if bbox:
        with pynput.keyboard.GlobalHotKeys({
                '<F4>': shutdown,
                '<F11>': lambda: casino_fingerprint(bbox),
                '<F6>': lambda: casino_keypad(bbox),
                '<F7>': lambda: cayo_fingerprint(bbox),
                '<F8>': lambda: cayo_voltage(bbox)}) as h:
            h.join()

if __name__ == "__main__":
    ctypes.windll.user32.SetProcessDPIAware()
    main()