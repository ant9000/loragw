import sys, os, json, re, time
import loragw
import gpiod
from gpiod.line import Direction, Value

SX1302_RESET_PIN=4      # SX1302 reset
SX1302_POWER_EN_PIN=17  # SX1302 power enable

if len(sys.argv) < 2:
    print("Usage: %s conf.json" % os.path.basename(sys.argv[0]))
    sys.exit(1)

json_cfg = open(sys.argv[1]).read()
cfg = json.loads(re.sub(r'/\*.*?\*/', '', json_cfg))["SX130x_conf"]

lines = gpiod.request_lines(
    "/dev/gpiochip0",
    consumer='loragw_spi',
    config={
        SX1302_RESET_PIN: gpiod.LineSettings(
            direction=Direction.OUTPUT, output_value=Value.INACTIVE
        ),
        SX1302_POWER_EN_PIN: gpiod.LineSettings(
            direction=Direction.OUTPUT, output_value=Value.INACTIVE
        ),
    }
)

# board configation
boardconf = loragw.lgw_conf_board_s()
boardconf.lorawan_public =  cfg["lorawan_public"]
assert(cfg["com_type"].upper() in ("SPI", "USB"))
boardconf.com_type = getattr(loragw, "LGW_COM_%s" % cfg["com_type"].upper())
boardconf.com_path = cfg["com_path"]
boardconf.clksrc = cfg["clksrc"]
boardconf.full_duplex = cfg["full_duplex"]

res = loragw.lgw_board_setconf(boardconf)
assert(res == loragw.LGW_HAL_SUCCESS)
print(
    "INFO: com_type %s, com_path %s, lorawan_public %d, clksrc %d, full_duplex %d" % (
     cfg["com_type"], boardconf.com_path, boardconf.lorawan_public, boardconf.clksrc, boardconf.full_duplex
))

# disable fine timestamping
tsconf = loragw.lgw_conf_ftime_s()
tsconf.enable = False
res = loragw.lgw_ftime_setconf(tsconf)
assert(res == loragw.LGW_HAL_SUCCESS)
print("INFO: Configuring legacy timestamp")

# disable sx1261
sx1261conf = loragw.lgw_conf_sx1261_s()
sx1261conf.enable = False
res = loragw.lgw_sx1261_setconf(sx1261conf)
assert(res == loragw.LGW_HAL_SUCCESS)

# configure RF chains - RX only
for i in range(loragw.LGW_RF_CHAIN_NB):
    radio_cfg = cfg.get("radio_%i" % i, None)
    if not radio_cfg:
        print("INFO: no configuration for radio %d" % i)
        continue
    rfconf = loragw.lgw_conf_rxrf_s()
    rfconf.enable = radio_cfg["enable"]
    rfconf.freq_hz = radio_cfg["freq"]
    rfconf.rssi_offset = radio_cfg["rssi_offset"]
    for k in "abcde":
        setattr(rfconf.rssi_tcomp, "coeff_%s" % k, radio_cfg["rssi_tcomp"]["coeff_%s" % k])
    assert(radio_cfg["type"].upper() in ("SX1255", "SX1257", "SX1250"))
    rfconf.type = getattr(loragw, "LGW_RADIO_TYPE_%s" % radio_cfg["type"].upper())
    rfconf.single_input_mode = radio_cfg.get("single_input_mode", False)
    rfconf.tx_enable = False

    res = loragw.lgw_rxrf_setconf(i, rfconf)
    assert(res == loragw.LGW_HAL_SUCCESS)
    print(
        "INFO: radio %i enabled (type %s), center frequency %u, RSSI offset %f, tx enabled %d, single input mode %d" % (
        i, radio_cfg["type"].upper(), rfconf.freq_hz, rfconf.rssi_offset, rfconf.tx_enable, rfconf.single_input_mode
    ))

# configure demodulators - enable all SFs
demodconf = loragw.lgw_conf_demod_s()
demodconf.multisf_datarate = loragw.LGW_MULTI_SF_EN;
res = loragw.lgw_demod_setconf(demodconf)
assert(res == loragw.LGW_HAL_SUCCESS) 

# configure Lora multi-SF channels
for i in range(loragw.LGW_MULTI_NB):
    chan_cfg = cfg.get("chan_multiSF_%d" % i, None)
    if not chan_cfg:
        print("INFO: no configuration for Lora multi-SF channel %d" % i)
        continue
    ifconf = loragw.lgw_conf_rxif_s()
    ifconf.enable = chan_cfg["enable"]
    if ifconf.enable:
        ifconf.rf_chain = chan_cfg["radio"]
        ifconf.freq_hz = chan_cfg["if"]

    res = loragw.lgw_rxif_setconf(i, ifconf)
    assert(res == loragw.LGW_HAL_SUCCESS)
    if ifconf.enable:
        print("INFO: Lora multi-SF channel %i>  radio %i, IF %i Hz, 125 kHz bw, SF 5 to 12" % (
            i, ifconf.rf_chain, ifconf.freq_hz
        ))
    else:
        print("INFO: Lora multi-SF channel %i disabled" % i)

if boardconf.com_type == loragw.LGW_COM_SPI:
    lines.set_value(SX1302_POWER_EN_PIN, Value.ACTIVE)
    lines.set_value(SX1302_RESET_PIN, Value.ACTIVE)
    time.sleep(0.1)
    lines.set_value(SX1302_RESET_PIN, Value.INACTIVE)
    time.sleep(0.1)

res = loragw.lgw_start()
assert(res == loragw.LGW_HAL_SUCCESS) 

res, eui = loragw.lgw_get_eui()
assert(res == loragw.LGW_HAL_SUCCESS) 
print("EUI: 0x%016x" % eui)

res = loragw.lgw_stop()
assert(res == loragw.LGW_HAL_SUCCESS) 
