# OpenOCD Flashing Tool for balenaFin

Lightweight precompiled binary for OpenOCD, used to flash the balenaFin coprocessor.

## Usage

Generates a device var `FLASHED` when the flashing is completed.
Remove this variable to allow flashing to resume.

## Notes 

Current external dependencies:

`install_packages`
- libftdi-dev
- ftdi-eeprom
- screen
- telnet
- jq

