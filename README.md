# LORAGW #

A SWIG wrapper for accessing Semtech `libloragw` SX1302 HAL from Python.

# Installation #

Tested on Debian 12 and 13:

```
sudo apt install build-essential git python3-dev python3-libgpiod swig
make
make test
```

With `make test` a basic sniffer is run. Modify the SX1302 pins in
`sniffer.py` if they differ from the specified ones:

```
SX1302_RESET_PIN=4      # SX1302 reset
SX1302_POWER_EN_PIN=17  # SX1302 power enable
```

Set the pins to `None` if you prefer to handle them externally.

To test transmission, the sniffer answers to received packets whose payload
starts with `b"PING"`. The feature can be disabled in `sniffer.py` with:

```
REPLY_TO_PINGS = False
```

# EXAMPLE USAGE #

```
import time
import loragw

SX1302_RESET_PIN=4
SX1302_POWER_EN_PIN=17

json_cfg = open('global_conf.json').read()

modem = loragw.SX1302(json_cfg, debug=True, reset_pin=SX1302_RESET_PIN, power_pin=SX1302_POWER_EN_PIN)
modem.start()

txpkt = loragw.TxPacket()
txpkt.modulation = loragw.MOD_LORA
txpkt.freq_hz = 868_300_000
txpkt.bandwidth = loragw.BW_125KHZ
txpkt.datarate = loragw.DR_LORA_SF7
txpkt.coderate = loragw.CR_LORA_4_5
txpkt.rf_power = 14
txpkt.payload = b'Hello, World!'
modem.send(txpkt)

try:
    while True:
        for rxpkt in modem.receive():
            print(f"Received: [{rxpkt.freq_hz/1e6:.1f}] {rxpkt.payload}")
        else:
            time.sleep(0.010) # 10 ms
            continue
except KeyboardInterrupt:
    pass
except Exception as e:
    print(f"ERROR: {e}")

modem.stop()
```

# TODO #

SX126x related functions - namely, spectral scan and LBT - are still missing.
