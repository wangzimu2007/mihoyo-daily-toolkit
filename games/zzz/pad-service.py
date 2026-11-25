import json
import os
import time

import vgamepad as vg

BASE = os.path.dirname(os.path.abspath(__file__))
CMD = os.path.join(BASE, 'pad-cmd.json')
ACK = os.path.join(BASE, 'pad-ack.json')
LOG = os.path.join(BASE, 'pad-service.log')


def log(msg):
    try:
        with open(LOG, "a", encoding="utf-8") as f:
            f.write("%s %s\n" % (time.strftime("%H:%M:%S"), msg))
    except Exception:
        pass


BTN = {
    "A": vg.XUSB_BUTTON.XUSB_GAMEPAD_A,
    "B": vg.XUSB_BUTTON.XUSB_GAMEPAD_B,
    "X": vg.XUSB_BUTTON.XUSB_GAMEPAD_X,
    "Y": vg.XUSB_BUTTON.XUSB_GAMEPAD_Y,
    "START": vg.XUSB_BUTTON.XUSB_GAMEPAD_START,
    "BACK": vg.XUSB_BUTTON.XUSB_GAMEPAD_BACK,
    "UP": vg.XUSB_BUTTON.XUSB_GAMEPAD_DPAD_UP,
    "DOWN": vg.XUSB_BUTTON.XUSB_GAMEPAD_DPAD_DOWN,
    "LEFT": vg.XUSB_BUTTON.XUSB_GAMEPAD_DPAD_LEFT,
    "RIGHT": vg.XUSB_BUTTON.XUSB_GAMEPAD_DPAD_RIGHT,
}


def main():
    log("service start, creating pad once")
    pad = vg.VX360Gamepad()
    time.sleep(0.5)
    log("pad ready (will stay connected)")
    last_mtime = 0
    while True:
        try:
            if os.path.exists(CMD):
                mtime = os.path.getmtime(CMD)
                if mtime != last_mtime:
                    last_mtime = mtime
                    with open(CMD, "r", encoding="utf-8-sig") as f:
                        cmd = json.load(f)
                    btn = str(cmd.get("btn", "A")).upper()
                    hold = float(cmd.get("hold", 0.12))
                    wait = float(cmd.get("wait", 0.0))
                    seq = cmd.get("seq")
                    if btn == "STOP":
                        log("stop requested")
                        break
                    if btn in BTN:
                        pad.press_button(button=BTN[btn])
                        pad.update()
                        time.sleep(hold)
                        pad.release_button(button=BTN[btn])
                        pad.update()
                        log("pressed %s hold=%.2f seq=%s" % (btn, hold, seq))
                        if wait > 0:
                            time.sleep(wait)
                    else:
                        log("unknown btn: %s" % btn)
                    try:
                        with open(ACK, "w", encoding="utf-8") as f:
                            json.dump({"ok": True, "btn": btn, "seq": seq, "at": time.time()}, f)
                    except Exception:
                        pass
        except Exception as exc:
            log("error: %s" % exc)
        time.sleep(0.15)


if __name__ == "__main__":
    main()
