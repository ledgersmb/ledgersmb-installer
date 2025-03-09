
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

## install (default)

```plain
  ledgersmb-installer install --version=1.12.0
  ledgersmb-installer --version=1.12.0
```

Downloads, unpacks and installs the indicated version, if possible with the
necessary O/S packages.

### Options

```plain
  --[no-]system-packages
  --target=<install directory>
  --local-lib=<installation directory for CPAN modules>
  --log-level=[fatal,error,warning,info,debug,trace]
  --[no-]verify-sig
  --version=<version>
```
