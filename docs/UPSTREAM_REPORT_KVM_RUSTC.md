# Upstream report (draft) — rustc/cargo under QEMU/KVM

Status: **documentado internamente; NÃO aberto upstream**.

Motivo: o CONTRIBUTING do Redox OS
(`https://gitlab.redox-os.org/redox-os/redox`) proíbe conteúdo gerado por
LLM (inclusive issues), sob pena de ban. Os issues do GitHub estão
desabilitados (`redox-os/redox`); o tracker oficial é o GitLab próprio.
Se um humano quiser submeter, usar o rascunho abaixo como referência
factual, reescrito em texto próprio, em
<https://gitlab.redox-os.org/redox-os/redox/-/issues>.

O conteúdo também está resumido em `REDOX_AUDIT.md` §2.15 e §3.1/10.

---

## Title suggestion

`rustc/cargo: UNHANDLED EXCEPTION under KVM; sysroot via dladdr + cargo -j parallelism under TCG`

## Summary

Running the self-hosted Rust toolchain in a QEMU/KVM guest, userland
`rustc`/`cargo` gets killed by the kernel with `UNHANDLED EXCEPTION`.
Under TCG the same image shows two separable userland problems instead:
rustc cannot locate its sysroot (`dladdr failed`), and cargo cannot query
CPU parallelism (`EINVAL`).

## Environment

- Host: Linux x86_64, QEMU 8.2.2
- Acceleration: KVM (also reproduced with `-accel tcg`)
- Image: `server.toml` + `dev-essential` (the `rust` recipe,
  `redox-2026-05-24` fork, `rustc 1.98.0-dev`, `cargo 1.98.0-dev`) + `git`;
  x86_64, serial console
- QEMU flags: `-machine q35 -cpu core2duo -smp 4 -m 4096` + NVMe disk + e1000 net

## Repro

As `user` in the guest, on a trivial crate:

```sh
cargo init --name hello
rustc src/main.rs -o hello
```

## Symptom (KVM)

The process dies without a userland message; the shell survives:

```
kernel::context::signal:INFO -- UNHANDLED EXCEPTION, CPU #0, PID 4X, NAME /usr/bin/rustc, CONTEXT 0xffffff7f8012da80
```

Seen both with and without `--sysroot`.

## Symptom (TCG, same image/session)

- `cargo init`: works.
- `rustc src/main.rs -o hello`: deterministic panic, no kernel involvement:

```
thread 'main' (1) panicked at compiler/rustc_session/src/filesearch.rs:255:60:
Failed finding sysroot: "dladdr failed"
error: the compiler unexpectedly panicked. This is a bug
```

- `cargo build`:

```
error: failed to determine the amount of parallelism available
  Invalid argument (os error 22)
```

## Observations / hypotheses

1. Under KVM the kernel terminates processes with `UNHANDLED EXCEPTION`
   for a load class that under TCG only yields a clean userland panic —
   looks acceleration-dependent (timers/clock/TLB?). Similar
   stabilization previously seen on aarch64 (TCG): the `nvmed` initfs
   daemon stack-overflows the guard page, so the pattern is not KVM-only.
2. rustc's ad-hoc sysroot discovery via `dladdr` fails on relibc, and the
   failure path dwarfs even `RUSTC_SYSROOT=/usr`/`--sysroot /usr` (the
   panic still fires). The cookbook invokes the toolchain as a package
   builder, so upstream CI does not hit the end-user case.
3. `std::thread::available_parallelism` returns `EINVAL` on Redox, so
   cargo cannot pick a default `-j`.

## Question

How does Redox expect end users to invoke `rustc`/`cargo` inside the OS
(outside the cookbook)? Today neither `--sysroot` nor the env var avoids
the panic, and the KVM exception appears unrelated to it.

Full serial repro logs were kept locally (host) during validation in
February–September 2026 sessions.