# AIOS Security Isolation - Gotchas

## Containment (Redox `contain` scheme)

### Status
The `ContainManager` in `security/src/contain.rs` provides the API surface for
isolating AI models using Redox's `contain` scheme, but the actual kernel-level
containment is **not yet implemented**.

### Why
Redox's `contain` scheme is a kernel-level isolation mechanism that requires:
1. The kernel to expose `/scheme/contain` as a writable filesystem
2. The `contain` recipe to be built into the image
3. The kernel to support the `contain` syscall

### What works
- `ContainManager::with_builtin_profiles()` - loads the `ai-model` and `dev`
  profiles as data. Unlike `new()`, it does **not** require `/scheme/contain`, so
  profile handling is usable and testable on a dev host.
- `register_profile()` / `get_profile()` / `profile_names()` - profile management
- `plan_container(name, profile)` - returns a `ContainerPlan`: the mounts,
  network grants, and resource limits the profile resolves to. Starts nothing.
  This is the surface for reviewing what a policy *claims* to isolate.
- `is_available()` - whether `/scheme/contain` is mounted

### What doesn't work
- `create_container()` - returns `NotImplemented`. It used to return a
  `ContainerInfo` with a fresh UUID and `ContainerStatus::Created`, which read
  as success: a caller could cache that id and believe an isolated process was
  running when none was. With no `contain` scheme to talk to, an error is the
  only honest answer.
- `start_container()` / `stop_container()` - return `NotImplemented`
- `list_containers()` - empty Vec, and `get_container()` returns `None`, for the
  same reason: nothing is ever created.

### Why not fabricate a `ContainerInfo`
A fabricated success is worse than an error here. The failure mode is silent: an
inference pipeline logs "container started", caches an id, and then runs the
model unisolated — while every log line claims isolation was applied. Prefer
`plan_container` when you want to inspect the intended isolation.

### To enable
1. Ensure the `contain` recipe is in the image profile
2. Add `contain` to `recipes/groups/dev-essential` or similar
3. Implement the actual scheme interaction in `create_container()`:
   ```rust
   // Pseudo-code for actual contain scheme interaction
   let mut contain = std::fs::File::open("/scheme/contain")?;
   // Write container config, read container ID, spawn process
   ```
4. Change `create_container` to return the real `ContainerInfo` and drop the
   `NotImplemented` return, then add integration tests with a real Redox image

## AI Permissions

### Status
The decision layer is implemented and tested: `security/src/enforce.rs` plus 20
negative tests in `security/tests/isolation.rs`. Kernel-level enforcement still
depends on the `contain` scheme.

### What works
- `Enforcer` evaluating an `AccessRequest` to a `PolicyDecision` with the
  matched rule id, plus a retained audit log of denials
- Default-deny: an unmatched request falls through to `policy.default_effect`,
  which the shipped templates set to `Deny`
- `PermissionSet` with `ResourceType` and `AccessLevel`
- `SecurityPolicy` with priority-based rules, deny-before-allow on ties
- `validate_deployment()` checks compatibility
- `aios-security` CLI: `authorize`, `check`, `describe`, `contain-profiles`,
  `contain-plan`

```sh
# Denies, exit 1:
aios-security authorize tinyllama filesystem read --scope /etc/shadow
# Allows, exit 0:
aios-security authorize tinyllama filesystem read --scope /var/lib/ai/models/m.gguf
```

### What doesn't work
- Kernel-level enforcement. This crate is the userland *decision* layer; the
  Redox kernel enforces what the policy tells it to, and a policy the kernel
  cannot express is not enforced at all.
- The tests prove a restricted policy denies the accesses it should. They are
  not a proof of isolation in the running system.

### To enable
1. Implement `ContainManager::create_container()` to actually spawn processes
2. Have the kernel consult the policy, or restrict via the `contain` scheme
3. Add integration tests against a real Redox image

## Scope matching holes (fixed — keep these regressions covered)

These were real grant-escalation bugs in `PolicyRule::matches`, both caused by
treating a scope as a string prefix. Both are now covered by tests; the
reasoning matters if the matching code is ever rewritten.

1. **Shared prefix.** `"/var/lib/ai/models_backup"` satisfied
   `starts_with("/var/lib/ai/models")`. Requiring a trailing separator fixes this
   one.
2. **Traversal.** `"/var/lib/ai/models/../../../etc/shadow"` also satisfies that
   prefix check — with *and* without the separator requirement, since the string
   really does start with the granted directory. A prefix check cannot catch it.

So `enforce::scope_contains` normalizes both sides, collapsing `.` and `..`, and
compares path components. Non-filesystem scopes still use a plain prefix, which
is the intended semantic for hosts and device nodes.

Known limit: normalization is lexical and does not resolve symlinks, so a
symlink inside an allowed directory pointing outside it is not caught at this
layer. That needs the caller's real path.

## Two more that were fixed in the same pass

- **Deny could be dead code.** `evaluate` returns the first matching rule, and
  rules were ordered by priority alone, so two rules at equal priority resolved
  by insertion order — a `deny` added after an `allow` never ran. Rules now sort
  by priority descending then effect, with `Deny` first. `normalize()`
  re-asserts the order for policies loaded from disk, so evaluation never
  depends on file order.
- **Unscoped allow silently became a deny.** `to_permission_set()` wrote
  `Some("")` for a rule with no scope, and `PermissionRule::allows` treats an
  empty scope as matching nothing. Every unscoped allow was inverted on the
  runtime path. It now leaves the scope unset.

## Netstack (Redox userspace TCP/IP)

### Status
The Redox `netstack` daemon **aborts on boot** under QEMU aarch64 with
`UNHANDLED EXCEPTION` at `src/header/stdlib/mod.rs:121`. This is an upstream
Redox bug, not an AIOS issue.

### Impact
- `edge status` and `edge models` fail in-guest because they require TCP
- `aios-deploy deploy` cannot transfer models to edge devices
- The `edge-ai` daemon can only serve on loopback (127.0.0.1)

### Workaround
None. This is a kernel/userspace bug in upstream Redox.

### To fix
This requires an upstream fix in the Redox `netstack` crate. The AIOS project
cannot fix this without modifying the Redox kernel, which is out of scope.

## NVMe Driver (aarch64 GICv3/ITS)

### Status
The NVMe driver in Redox kernel hangs at namespace enumeration on aarch64
with GICv3/ITS enabled. The IRQ is never delivered.

### Impact
- aarch64 image cannot boot to login prompt
- Edge AI OS on aarch64 cannot start

### Workaround
Use `-machine virt,gic-version=3,its=on,iommu=smmuv3` in QEMU (partial fix,
still hangs at namespace enumeration)

### To fix
Requires upstream fix in Redox kernel's NVMe driver for GICv3/ITS support.