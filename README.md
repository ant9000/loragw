# LORAGW #

This is a simple SWIG wrapper for accessing Semtech `libloragw` SX1302 HAL from
Python. Just do `make`, it will fetch all relevant code and create the
necessary wrappers.

With `make test` a very basic sniffer is run. Modify the SX1302 pins in
`sniffer.py` if they differ from the specified ones.
