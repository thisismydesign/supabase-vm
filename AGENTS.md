# supabase-vm

Self-hosted Supabase, one VM per project, on a VPS. The VM is the boundary between production data and everything else on the host.

## Docs

- `README.md` — what it is, how to create, expose, deploy to and operate a VM.
- `AGENTS.md` — how to work here.

## Layout

```
host/                    run on the VPS: create a VM, save its state, deploy functions into it
vm/                      pushed into the VM: bootstrap, Supabase setup, exposure, compose override
state/<vm>/              saved identity of a VM (.env, Tailscale, SSH host keys); gitignored
.env.<vm>                local copy of a VM's secrets; gitignored
```

## Rules

- MUST NOT read `.env*` or `state/`; they hold production secrets.
- MUST NOT create, delete, resize or expose a VM without instruction; each touches production.
- Changes to what runs inside a VM MUST go through `vm/` so the next VM gets them; nothing is configured by hand in a VM only.
- The Supabase bundle is upstream's; MUST NOT edit its files, only `.env` and compose overrides.
- Code MUST explain itself; comments SHOULD NOT be needed. Comments and docs MAY record a reason the code cannot show and MUST NOT explain how it works.
- All prose — comments, docs, messages — MUST stay terse; prescriptions use RFC 2119.
