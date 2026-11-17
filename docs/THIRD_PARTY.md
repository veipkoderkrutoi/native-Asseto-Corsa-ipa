# Third-party components and licenses

The repository vendors rustyAC source because our Cargo path dependencies require
it. No Assetto Corsa game assets are vendored.

| Component | Path | License | Notes |
|---|---|---|---|
| rustyAC game / physics / render / game / GUI / net | `third_party/rustyAC-src/rustyAC-master/crates/` | **GPL-3.0-or-later** | License text in `LICENSE-GPL`; our `ac-ios-runtime` is GPL-3.0-or-later accordingly |
| rustyAC math / content / dxbc / gateway / web helpers | same tree | **MIT OR Apache-2.0** | Texts in `LICENSE-MIT`, `LICENSE-APACHE` |
| rustyac-ode (ODE 0.13.1 port) | same tree | **BSD-3-Clause** | licenses in crate manifest |
| wgpu / objc2 / raw-window-metal etc. | Cargo registry (resolved by Cargo.lock) | various permissive (MIT/Apache/BSD) | downloaded during CI; no vendored binaries committed |
| XcodeGen / Homebrew packages | installed by the workflow | MIT / respective licenses | not vendored |

Verify locally:

```powershell
Get-ChildItem third_party\rustyAC-src\rustyAC-master\LICENSE*
Select-String -Path third_party\rustyAC-src\rustyAC-master\crates\*\Cargo.toml -Pattern '^license'
```

Important: GPL-3.0 requires that a distributed binary be accompanied by the
corresponding source and license notices. The public repository contains that source.
No Kunos Simulazioni / 505 Games content is included; the app reads content only from
a folder the user imports at runtime.
