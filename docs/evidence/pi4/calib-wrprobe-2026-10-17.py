#!/usr/bin/env python3
"""Calibração de escrita: boota UMA CÓPIA do artefato em QEMU sem -snapshot.

Objetivo: verificar se o boot (u-boot -> kernel -> login) grava algo no
redoxfs da imagem (p3). Se gravar, então comparar o cartão pós-boot com a
imagem mestra detecta se o kernel do AIOS chegou a rodar no Pi real.

- Nenhum comando é enviado no serial (ninguém loga): só espera o prompt.
- Ao aparecer "redox login:", aguarda 20s e desliga o QEMU.
- A imagem usada é /tmp/opencode/pi4tb/wrtest.img (cópia; o artefato não é tocado).
"""
import json, os, select, socket, subprocess, time

QEMU = "/tmp/opencode/qemusys/q9/root/usr/bin/qemu-system-aarch64"
BASE = "/tmp/opencode/pi4tb"
IMG = f"{BASE}/wrtest.img"

env = os.environ.copy()
env["LD_LIBRARY_PATH"] = "/tmp/opencode/qemusys/q9/root/usr/lib/x86_64-linux-gnu:/tmp/opencode/qemusys/q9/root/usr/lib"
env["QEMU_MODULE_DIR"] = f"{BASE}/mod"

QMP_SOCK = f"{BASE}/wrprobe.sock"
SER_SOCK = f"{BASE}/serwr.sock"
SER_LOG = f"{BASE}/wrprobe.ser"
for path in (QMP_SOCK, SER_SOCK, SER_LOG):
    try:
        os.unlink(path)
    except FileNotFoundError:
        pass

args = [QEMU, "-M", "raspi4b", "-cpu", "cortex-a72", "-smp", "4", "-m", "2048",
        "-display", "none", "-no-reboot",
        "-kernel", f"{BASE}/uboot-pi4/rpi_4-u-boot.bin", "-dtb", f"{BASE}/dtb-emmc-swap.dtb",
        "-drive", f"if=sd,file={IMG},format=raw",
        "-chardev", f"socket,id=ser0,path={SER_SOCK},server=on,wait=off,logfile={SER_LOG}",
        "-serial", "chardev:ser0",
        "-qmp", f"unix:{QMP_SOCK},server,nowait"]

log = open(f"{BASE}/wrprobe.err", "wb")
proc = subprocess.Popen(args, env=env, stdout=log, stderr=log, cwd=BASE)


def connect(path, tries=100):
    for _ in range(tries):
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.connect(path)
            return s
        except Exception:
            time.sleep(0.2)
    return None


qmp = connect(QMP_SOCK)
if qmp is None:
    print("ERRO: QMP nao subiu")
    proc.kill()
    raise SystemExit(1)
qf = qmp.makefile("rwb")


def recv():
    line = qf.readline().decode(errors="replace")
    return json.loads(line) if line.strip() else None


recv()


def qcmd(name, arguments=None):
    msg = {"execute": name}
    if arguments:
        msg["arguments"] = arguments
    qf.write((json.dumps(msg) + "\n").encode())
    qf.flush()
    while True:
        r = recv()
        if r is None:
            return None
        if "return" in r or "error" in r:
            return r


qcmd("qmp_capabilities")

serc = connect(SER_SOCK)
if serc is None:
    print("ERRO: socket serial nao subiu")
    proc.kill()
    raise SystemExit(1)
serc.setblocking(False)

buf = bytearray()


def pump(seconds):
    t0 = time.time()
    while time.time() - t0 < seconds:
        r, _, _ = select.select([serc], [], [], 0.2)
        if r:
            try:
                data = serc.recv(65536)
            except BlockingIOError:
                continue
            if data:
                buf.extend(data)


t0 = time.time()
ok = False
while time.time() - t0 < 330:
    pump(1)
    if b"redox login:" in bytes(buf[-400000:]):
        ok = True
        break

dt = time.time() - t0
print("login prompt: " + (("OK t+%.0fs" % dt) if ok else ("TIMEOUT %.0fs" % dt)), flush=True)
if ok:
    pump(20)
    print("20s extra de settle; desligando.", flush=True)

qcmd("quit")
time.sleep(2)
if proc.poll() is None:
    proc.terminate()
time.sleep(1)
if proc.poll() is None:
    proc.kill()
print("QEMU parado. bytes no serial:", len(buf))
