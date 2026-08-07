# Security Policy

## Supported versions

| Version | Supported |
| --- | --- |
| Latest release on GitHub | Yes |
| Older tags | Best effort |

## Reporting a vulnerability

If you find a security issue in ExoOS (privilege path, path traversal in playbook load, elevation abuse, supply-chain in shipped UI/assets):

1. Prefer a **private** GitHub security advisory on [ImAvgErix/ExoOS](https://github.com/ImAvgErix/ExoOS)
2. Or contact the maintainer via the profile on [github.com/ImAvgErix](https://github.com/ImAvgErix)

Please do **not** open a public issue for exploitable privilege bugs until a fix ships.

## Scope

**In scope**

- ExoForge engine and CLI  
- ExoOS.App host and WebView2 bridge  
- Shipped playbook YAML and scripts under `playbooks/exoos`  
- Install / publish scripts  

**Out of scope**

- Intentional damage after the user types `EXOOS` or passes `--live`  
- Third-party software the playbook optionally installs  
- Windows itself  

## Safe defaults

- Dry-run is the default path in docs and the Preview button  
- Live apply requires explicit confirmation  
- Never commit keys, tokens, or account credentials  
