
# NAME

ledgersmb-installer - An installer for LedgerSMB, targetting as many platforms as possible
on which the LedgerSMB server can run.

# SYNOPSIS

```bash
  ledgersmb-installer install --log-level=error --target=/srv/ledgersmb --version=1.12.0
```
# COMMANDS

## compute

```plain
  ledgersmb-installer compute --version=1.12.0
```

Computes the list of packages fulfilling the module dependencies.

**Note**: The computation currently does not take the module versions into account.

## download

## install

```plain
  ledgersmb-installer install --version=1.12.0
  ledgersmb-installer --version=1.12.0
```

Downloads, unpacks and installs the indicated version, if possible with the
necessary O/S packages.

## help

### Options

```plain
  --[no-]system-packages
  --target=<install directory>
  --local-lib=<installation directory for CPAN modules>
  --log-level=[fatal,error,warning,info,debug,trace]
  --[no-]verify-sig
  --version=<version>
```


# INSTALLER PROCESS

```mermaid
flowchart TD
    pre_A@{ shape: start }
    pre_A --> pre_B{Known platform}
    pre_B --> |Yes| pre_C{Have precomputed deps}
    pre_B --> |No| pre_D(Compute module deps)
    pre_C --> |Yes| pre_C1{Can install pkgs}
    pre_C --> |No| pre_D
    pre_C1 --> |Yes| pre_K
    pre_C1 --> |No| pre_D
    pre_D --> pre_E{Have suitable system perl}

    pre_E --> |Yes| pre_F{Can install pkgs && <br>Have 'pkg compute' prereqs}
    pre_E --> |No| pre_E2{Have libxml2 prereq}
    pre_E2 --> |Yes| pre_E6
    pre_E2 --> |No| pre_E3{Can install pkgs}
    pre_E3 --> |Yes| pre_E4(Install libxml2)
    pre_E3 --> |No| pre_E5(Install Alien::LibXML)
    pre_E4 --> pre_E6{Have libpq prereq}
    pre_E5 --> pre_E6
    pre_E6 --> |No| pre_E7{Can install pkgs}
    pre_E6 --> |Yes| pre_G
    pre_E7 --> |No| pre_J
    pre_E7 --> |Yes| pre_E8(Install libpq)
    pre_E8 --> pre_G

    pre_G{Can install perlbrew}
    pre_F --> |Yes| pre_H(Map pkg deps)
    pre_F --> |No| pre_F2{Have libxml2 prereq}
    pre_G --> |No| pre_J(**bail out**)
    pre_G --> |Yes| pre_I(Install perlbrew)

    pre_H --> pre_K(Install packaged modules)
    pre_K --> pre_K2{Have unpackaged modules}
    pre_K2 --> |No| pre_Z
    pre_I --> pre_M

    pre_F2 --> |Yes| pre_F6(Install libxml2)
    pre_F2 --> |No| pre_F3{Can install pkgs}
    pre_F3 --> |Yes| pre_F4(install libxml2)
    pre_F3 --> |No| pre_F5(Install Alien::LibXML)
    pre_F4 --> pre_F6{Have libpq prereq}
    pre_F5 --> pre_F6
    pre_F6 --> |Yes| pre_L
    pre_F6 --> |No| pre_F7{Can install pkgs}
    pre_F7 --> |Yes| pre_F8(Install libpq)
    pre_F7 --> |No| pre_J
    pre_F8 --> pre_L

    pre_K2 --> |Yes| pre_L{Can compile modules}
    pre_L --> |Yes| pre_M(Install CPAN modules)
    pre_L --> |No| pre_J
    pre_M --> pre_Z
    pre_Z@{ shape: stop }
```
