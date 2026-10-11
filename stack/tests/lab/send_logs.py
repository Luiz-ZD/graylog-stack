#!/usr/bin/env python3
"""Envia syslog RFC3164 sintético. Mensagens 'win' imitam o WinCollect (campos separados por TAB)."""
import argparse, socket, time

WIN = ("{host} AgentDevice=WindowsLog\tAgentLogFile=Application\tPluginVersion=WC.MSEVEN6.10.1.13.12\t"
       "Source=Application Error\tComputer={host}.lab.local\tUser=\tDomain=\tEventID={eid}\tEventIDCode={eid}\t"
       "EventType={etype}\tEventCategory=100\tRecordNumber={n}\tTimeGenerated=1789864427\tTimeWritten=1789864427\t"
       "Level={wlevel}\tKeywords=Classic\tTask=100\tOpcode=Info\tMessage=lab {tag} #{n}")

def build(kind, host, n, level, tag, wlevel, etype, eid):
    pri = 1 * 8 + level  # facility user
    ts = time.strftime("%b %e %H:%M:%S")
    body = (WIN.format(host=host, n=n, tag=tag, wlevel=wlevel, etype=etype, eid=eid)
            if kind == "win" else f"{host} lab[{n}]: {tag} message {n}")
    return f"<{pri}>{ts} {body}"

def main():
    a = argparse.ArgumentParser()
    a.add_argument("--host", default="127.0.0.1"); a.add_argument("--port", type=int)
    a.add_argument("--kind", choices=["win", "linux"], required=True)
    a.add_argument("--proto", choices=["tcp", "udp"], required=True)
    a.add_argument("--count", type=int, default=10); a.add_argument("--level", type=int, default=3)
    a.add_argument("--wlevel", default="Error"); a.add_argument("--etype", type=int, default=1)
    a.add_argument("--eid", type=int, default=1000)
    a.add_argument("--src", default="LAB-HOST-01"); a.add_argument("--tag", default="t")
    a.add_argument("--rate", type=int, default=0, help="msgs/s (0 = sem limite)")
    a = a.parse_args()
    port = a.port or (3514 if a.proto == "tcp" else 4514)
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM if a.proto == "tcp" else socket.SOCK_DGRAM)
    if a.proto == "tcp": s.connect((a.host, port))
    t0 = time.time()
    for n in range(1, a.count + 1):
        m = build(a.kind, a.src, n, a.level, a.tag, a.wlevel, a.etype, a.eid)
        if a.proto == "tcp": s.sendall((m + "\n").encode())
        else: s.sendto(m.encode(), (a.host, port))
        if a.rate and n % a.rate == 0:
            time.sleep(max(0, (n / a.rate) - (time.time() - t0)))
    s.close(); print(f"SENT={a.count}")

if __name__ == "__main__":
    main()
