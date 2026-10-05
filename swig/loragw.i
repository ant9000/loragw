%module loragw

%include typemaps.i
%include "stdint.i"
%include "carrays.i"
%include "cdata.i"

%begin %{
#define SWIG_PYTHON_STRICT_BYTE_CHAR
%}

%{
#include "libloragw/include/loragw_hal.h"
%}

typedef enum com_type_e {
    LGW_COM_SPI,
    LGW_COM_USB,
    LGW_COM_UNKNOWN
} lgw_com_type_t;

int lgw_get_eui(uint64_t * OUTPUT);

%include "libloragw/include/loragw_hal.h"

%pythonappend lgw_pkt_rx_array_new %{
    # Wrap it automatically
    newval = lgw_pkt_rx_array.frompointer(val)
    newval.ptr_retain = val
    val = newval
%}

%newobject lgw_pkt_rx_array_new();

%inline %{
  struct lgw_pkt_rx_s *lgw_pkt_rx_array_new(size_t n) {
    struct lgw_pkt_rx_s *arr = (struct lgw_pkt_rx_s *)calloc(n, sizeof(struct lgw_pkt_rx_s));
    return arr;
  }
%}

%array_class(struct lgw_pkt_rx_s, lgw_pkt_rx_array);
%array_functions(struct lgw_tx_gain_s, lgw_tx_gain_s_array);

%pythonbegin %{
import json, re, time
import gpiod
from gpiod.line import Direction, Value
%}

%pythoncode %{

class RxPacket:
    def __init__(self, rxpkt):
        self.__dict__["__rxpkt"] = rxpkt
    def __getattribute__(self, key):
        if key == "__dict__":
            return super().__getattribute__(key)
        p = self.__dict__["__rxpkt"]
        if key == "payload":
            return cdata(p.payload, p.size)
        elif key == "status":
            return {STAT_NO_CRC: "NO CRC", STAT_CRC_BAD: "BAD CRC", STAT_CRC_OK: "CRC OK"}.get(p.status, "UNDEF")
        elif key == "modulation":
            return {MOD_CW: "CW", MOD_LORA: "LORA", MOD_FSK: "FSK"}.get(p.modulation, "UNDEF")
        elif key == "bandwidth":
            return {BW_500KHZ: "500kHz", BW_250KHZ: "250kHz", BW_125KHZ: "125kHz"}.get(p.bandwidth, "UNDEF")
        elif key == "coderate":
            return "4/%d" % (p.coderate + 4)
        else:
            return getattr(p, key)

class SX1302:
    NB_PKT_MAX = 255
    def __init__(self, json_cfg, debug=False, reset_pin=None, power_pin=None):
        self.debug = debug
        self.load_config(json_cfg)
        self.reset_pin = reset_pin
        self.power_pin = power_pin
        self.lines = None
        if reset_pin and power_pin:
            self.lines = gpiod.request_lines(
                "/dev/gpiochip0",
                consumer='loragw_spi',
                config={
                    reset_pin: gpiod.LineSettings(
                        direction=Direction.OUTPUT, output_value=Value.INACTIVE
                    ),
                    power_pin: gpiod.LineSettings(
                        direction=Direction.OUTPUT, output_value=Value.INACTIVE
                    ),
                }
            )
        self.__rxpkts = lgw_pkt_rx_array_new(self.NB_PKT_MAX)

    def debug_print(self, message):
        if self.debug:
            print(message)

    def load_config(self, json_cfg):
        conf_obj_name = "SX130x_conf"
        try:
            cfg = json.loads(re.sub(r'/\*.*?\*/', '', json_cfg))
        except:
            raise Exception("ERROR: config is not a valid JSON string")
        try:
            cfg = cfg[conf_obj_name]
        except:
            raise Exception("INFO: config does not contain a JSON object named %s" % conf_obj_name)

        # board configuration
        boardconf = lgw_conf_board_s()
        try:
            com_type = cfg["com_type"]
        except:
            raise Exception("ERROR: com_type must be configured in config")
        if com_type.upper() == "SPI":
            boardconf.com_type = LGW_COM_SPI
        elif com_type.upper() == "USB":
            boardconf.com_type = LGW_COM_USB
        else:
            raise Exception("ERROR: invalid com type: %s (should be SPI or USB)" % com_type)
        try:
            boardconf.com_path = cfg["com_path"].encode("utf-8")
        except:
            raise Exception("ERROR: com_path must be configured in config")
        lorawan_public = cfg.get("lorawan_public", None)
        if lorawan_public in (True, False):
            boardconf.lorawan_public = lorawan_public
        else:
            self.debug_print("WARNING: Data type for lorawan_public seems wrong, please check")
            boardconf.lorawan_public = lorawan_public
        clksrc = cfg.get("clksrc", None)
        if type(clksrc) == int:
            boardconf.clksrc = clksrc
        else:
            self.debug_print("WARNING: Data type for clksrc seems wrong, please check")
            boardconf.clksrc = 0
        full_duplex = cfg.get("full_duplex", None)
        if full_duplex in (True, False):
            boardconf.full_duplex = full_duplex
        else:
            self.debug_print("WARNING: Data type for full_duplex seems wrong, please check")
            boardconf.full_duplex = False
        self.debug_print(
            "INFO: com_type %s, com_path %s, lorawan_public %d, clksrc %d, full_duplex %d" % (
            com_type.upper(), boardconf.com_path, boardconf.lorawan_public, boardconf.clksrc, boardconf.full_duplex))
        res = lgw_board_setconf(boardconf)
        if res != LGW_HAL_SUCCESS:
            raise Exception("ERROR: Failed to configure board")

        # antenna gain configuration
        antenna_gain = cfg.get("antenna_gain", None)
        if type(antenna_gain) == int:
            self.antenna_gain = antenna_gain & 0xFF
        else:
            self.debug_print("WARNING: Data type for antenna_gain seems wrong, please check")
            self.antenna_gain = 0
        self.debug_print("INFO: antenna_gain %d dBi" % self.antenna_gain)

        # fine timestamping configuration
        ts_cfg = cfg.get("fine_timestamp", None)
        if ts_cfg is None:
            self.debug_print("INFO: config does not contain a JSON object for fine timestamp")
        else:
            tsconf = lgw_conf_ftime_s()
            enable = ts_cfg.get("enable", None)
            if enable in (True, False):
                tsconf.enable = enable
            else:
                self.debug_print("WARNING: Data type for fine_timestamp.enable seems wrong, please check")
                tsconf.enable = False
            if tsconf.enable:
                try:
                    mode = str(tg_cfg["mode"])
                except:
                    raise Exception("ERROR: fine_timestamp.mode must be configured in config")
                if mode.upper() == "HIGH_CAPACITY":
                    tsconf.mode = LGW_FTIME_MODE_HIGH_CAPACITY
                elif mode.upper() == "ALL_SF":
                    tsconf.mode = LGW_FTIME_MODE_ALL_SF
                else:
                    raise Exception("ERROR: invalid fine timestamp mode: %s (should be high_capacity or all_sf)" % mode)
                self.debug_print("INFO: Configuring precision timestamp with %s mode" % mode)
                res = lgw_ftime_setconf(tsconf)
                if res != LGW_HAL_SUCCESS:
                    raise Exception("ERROR: Failed to configure fine timestamp")
            else:
                self.debug_print("INFO: Configuring legacy timestamp")

        # sx1261 configuration
        sx1261_cfg = cfg.get("sx1261_conf", None)
        if sx1261_cfg is None:
            self.debug_print("INFO: no configuration for SX1261")
        else:
            sx1261conf = lgw_conf_sx1261_s()
            spi_path = sx1261_cfg.get("spi_path", None)
            if type(spi_path) == str:
                sx1261conf.spi_path = spi_path.encode("utf-8")
            else:
                self.debug_print("INFO: SX1261 spi_path is not configured in config")
            rssi_offset = sx1261_cfg.get("rssi_offset", None)
            if type(rssi_offset) == int:
                sx1261conf.rssi_offset = rssi_offset & 0xFF
            else:
                self.debug_print("WARNING: Data type for sx1261_conf.rssi_offset seems wrong, please check")
                sx1261conf.rssi_offset = 0

            # spectral scan configuration
            ss_cfg = sx1261_cfg.get("spectral_scan", None)
            if ss_cfg is None:
                self.debug_print("INFO: no configuration for Spectral Scan")
            else:
                # TODO
                self.debug_print("TODO: process configuration for Spectral Scan - disabling for now")
                sx1261conf.enable = False

            # listen before talk configuration
            lbt_cfg = sx1261_cfg.get("lbt", None)
            if lbt_cfg is None:
                self.debug_print("INFO: no configuration for LBT")
            else:
                # TODO
                self.debug_print("TODO: process configuration for LBT - disabling for now")
                sx1261conf.lbt_conf.enable = False

            res = lgw_sx1261_setconf(sx1261conf)
            if res != LGW_HAL_SUCCESS:
                raise Exception("ERROR: Failed to configure the SX1261 radio")

        # RF chains configuration
        self.tx_enable = {}
        self.tx_freq_min = {}
        self.tx_freq_max = {}
        self.tx_lut = {}
        for i in range(LGW_RF_CHAIN_NB):
            radio_cfg = cfg.get("radio_%i" % i, None)
            if not radio_cfg:
                self.debug_print("INFO: no configuration for radio %d" % i)
                continue
            rfconf = lgw_conf_rxrf_s()
            rfconf.enable = radio_cfg.get("enable", False)
            if not rfconf.enable:
                self.debug_print("INFO: radio %i disabled" % i)
            else:
                freq = radio_cfg.get("freq", None)
                if type(freq) == int:
                    rfconf.freq_hz = freq
                rssi_offset = radio_cfg.get("rssi_offset", None)
                if type(rssi_offset) in (int, float):
                    rfconf.rssi_offset = float(rssi_offset)
                for k in "abcde":
                    name = "coeff_%s" % k
                    coeff = radio_cfg.get("rssi_tcomp", {}).get(name, None)
                    if type(coeff) in (int, float):
                        setattr(rfconf.rssi_tcomp, name, float(coeff))
                radio_type = radio_cfg.get("type", None)
                if radio_type == "SX1255":
                    rfconf.type = LGW_RADIO_TYPE_SX1255
                elif radio_type == "SX1257":
                    rfconf.type = LGW_RADIO_TYPE_SX1257
                elif radio_type == "SX1250":
                    rfconf.type = LGW_RADIO_TYPE_SX1250
                else:
                    self.debug_print("WARNING: invalid radio type: %s (should be SX1255 or SX1257 or SX1250)" % radio_type)
                rfconf.single_input_mode = radio_cfg.get("single_input_mode", False)

                rfconf.tx_enable = radio_cfg.get("tx_enable", False)
                self.tx_enable[i] = rfconf.tx_enable
                if rfconf.tx_enable:
                    # tx is enabled on this rf chain, we need its frequency range
                    self.tx_freq_min[i] = radio_cfg.get("tx_freq_min", 0)
                    self.tx_freq_max[i] = radio_cfg.get("tx_freq_max", 0)
                    if self.tx_freq_min[i] == 0 or self.tx_freq_max[i] == 0:
                        self.debug_print("WARNING: no frequency range specified for TX rf chain %d" % i)
                    # set configuration for tx gains
                    self.tx_lut[i] = lgw_tx_gain_lut_s()
                    tx_gain_lut = radio_cfg.get("tx_gain_lut", None)
                    if type(tx_gain_lut) == list and len(tx_gain_lut):
                        self.tx_lut[i].size = len(tx_gain_lut)
                        # detect if we have a sx125x or sx1250 configuration
                        if "pwr_idx" in tx_gain_lut[0]:
                            self.debug_print("INFO: Configuring Tx Gain LUT for rf_chain %u with %u indexes for sx1250" % (i, self.tx_lut[i].size))
                            sx1250_tx_lut = True
                        else:
                            self.debug_print("INFO: Configuring Tx Gain LUT for rf_chain %u with %u indexes for sx125x" % (i, self.tx_lut[i].size))
                            sx1250_tx_lut = False
                        # parse the table
                        lut = new_lgw_tx_gain_s_array(TX_GAIN_LUT_SIZE_MAX)
                        for j in range(self.tx_lut[i].size):
                            l = lgw_tx_gain_s()
                            if j >= TX_GAIN_LUT_SIZE_MAX:
                                self.debug_print("ERROR: TX Gain LUT [%u] index %d not supported, skip it" % (i, j))
                                self.tx_lut[i].size = TX_GAIN_LUT_SIZE_MAX
                                break
                            rf_power = tx_gain_lut[i].get("rf_power", None)
                            if type(rf_power) == int:
                                l.rf_power = rf_power & 0xFF
                            else:
                                self.debug_print("WARNING: Data type for %s[%d] seems wrong, please check" % ("rf_power", j))
                                l.rf_power = 0
                            pa_gain = tx_gain_lut[i].get("pa_gain", None)
                            if type(pa_gain) == int:
                                l.pa_gain = pa_gain & 0xFF
                            else:
                                self.debug_print("WARNING: Data type for %s[%d] seems wrong, please check" % ("pa_gain", j))
                                l.pa_gain = 0
                            if not sx1250_tx_lut:
                                dig_gain = tx_gain_lut[i].get("dig_gain", None)
                                if type(dig_gain) == int:
                                    l.dig_gain = dig_gain & 0xFF
                                else:
                                    self.debug_print("WARNING: Data type for %s[%d] seems wrong, please check" % ("dig_gain", j))
                                    self.tx_lut[i].l.dig_gain = 0
                                dac_gain = tx_gain_lut[i].get("dac_gain", None)
                                if type(dac_gain) == int:
                                    l.dac_gain = dac_gain & 0xFF
                                else:
                                    self.debug_print("WARNING: Data type for %s[%d] seems wrong, please check" % ("dac_gain", j))
                                    l.dac_gain = 0
                                mix_gain = tx_gain_lut[i].get("mix_gain", None)
                                if type(mix_gain) == int:
                                    l.mix_gain = mix_gain & 0xFF
                                else:
                                    self.debug_print("WARNING: Data type for %s[%d] seems wrong, please check" % ("mix_gain", j))
                                    l.mix_gain = 0
                            else:
                                l.mix_gain = 5
                                pwr_idx = tx_gain_lut[i].get("pwr_idx", None)
                                if type(pwr_idx) == int:
                                    l.pwr_idx = pwr_idx & 0xFF
                                else:
                                    self.debug_print("WARNING: Data type for %s[%d] seems wrong, please check" % ("pwr_idx", j))
                                    l.pwr_idx = 0
                            lgw_tx_gain_s_array_setitem(lut, j, l)
                        self.tx_lut[i].lut = lut
                        res = lgw_txgain_setconf(i, self.tx_lut[i])
                        if (res != LGW_HAL_SUCCESS):
                            raise Exception("ERROR: Failed to configure concentrator TX Gain LUT for rf_chain %u" % i)
                    else:
                        self.debug_print("WARNING: No TX gain LUT defined for rf_chain %u" % i)
                print(
                    "INFO: radio %i enabled (type %s), center frequency %u, RSSI offset %f, tx enabled %d, single input mode %d" % (
                    i, radio_type, rfconf.freq_hz, rfconf.rssi_offset, rfconf.tx_enable, rfconf.single_input_mode))
                res = lgw_rxrf_setconf(i, rfconf)
                if res != LGW_HAL_SUCCESS:
                    raise Exception("ERROR: invalid configuration for radio %i" % i)

        # demodulators configuration
        demod_cfg = cfg.get("chan_multiSF_All", None)
        if demod_cfg is None:
            self.debug_print("INFO: no configuration for LoRa multi-SF spreading factors enabling")
        else:
            demodconf = lgw_conf_demod_s()
            demodconf.multisf_datarate = LGW_MULTI_SF_EN;
            sf_list = demod_cfg.get("spreading_factor_enable", None)
            if sf_list and len(sf_list) <= LGW_MULTI_NB:
                for i, sf in enumerate(sf_list):
                    if type(sf) == int and 5 <= sf <= 12:
                        demodconf.multisf_datarate |= (1 << (sf - 5))
                    else:
                        self.debug_print("WARNING: failed to parse chan_multiSF_All.spreading_factor_enable (wrong value at idx %d)" % i)
                        demodconf.multisf_datarate = LGW_MULTI_SF_EN # enable all SFs
                        break
            else:
                self.debug_print("WARNING: failed to parse chan_multiSF_All.spreading_factor_enable");
                demodconf.multisf_datarate = LGW_MULTI_SF_EN # enable all SFs

            res = lgw_demod_setconf(demodconf)
            if res != LGW_HAL_SUCCESS:
                raise Exception("ERROR: invalid configuration for demodulation parameters")

        # LoRa multi-SF channels configuration (bandwidth cannot be set)
        for i in range(LGW_MULTI_NB):
            chan_cfg = cfg.get("chan_multiSF_%d" % i, None)
            if chan_cfg is None:
                print("INFO: no configuration for Lora multi-SF channel %d" % i)
                continue
            ifconf = lgw_conf_rxif_s()
            ifconf.enable = chan_cfg.get("enable", False)
            if not ifconf.enable:
                self.debug_print("INFO: Lora multi-SF channel %i disabled" % i)
            else:
                radio = chan_cfg.get("radio", 0)
                ifconf.rf_chain = type(radio) == int and radio or 0
                freq_hz = chan_cfg.get("if", 0)
                ifconf.freq_hz = type(freq_hz) == int and freq_hz or 0
                self.debug_print("INFO: Lora multi-SF channel %i>  radio %i, IF %i Hz, 125 kHz bw, SF 5 to 12" % (
                    i, ifconf.rf_chain, ifconf.freq_hz))
            res = lgw_rxif_setconf(i, ifconf)
            if res != LGW_HAL_SUCCESS:
                raise Exception("ERROR: invalid configuration for Lora multi-SF channel %i" % i)

        # LoRa standard channel configuration
        chan_cfg = cfg.get("chan_Lora_std", None)
        if chan_cfg is None:
            print("INFO: no configuration for Lora standard channel")
        else:
            ifconf = lgw_conf_rxif_s()
            ifconf.enable = chan_cfg.get("enable", False)
            if not ifconf.enable:
                self.debug_print("INFO: Lora standard channel disabled")
            else:
                radio = chan_cfg.get("radio", 0)
                ifconf.rf_chain = type(radio) == int and radio or 0
                freq_hz = chan_cfg.get("if", 0)
                ifconf.freq_hz = type(freq_hz) == int and freq_hz or 0
                bw = chan_cfg.get("bandwidth", 0)
                if type(bw) != int:
                    bw = 0
                ifconf.bandwidth = {500000: BW_500KHZ, 250000: BW_250KHZ, 125000: BW_125KHZ}.get(bw, BW_UNDEFINED)
                sf = chan_cfg.get("spread_factor", 0)
                if type(sf) != int:
                    sf = 0
                if 5 <= sf <= 12:
                    ifconf.datarate = sf
                else:
                    ifconf.datarate = DR_UNDEFINED
                ifconf.implicit_hdr = chan_cfg.get("implicit_hdr", False) and True or False
                if ifconf.implicit_hdr:
                    implicit_payload_length = chan_cfg.get("implicit_payload_length", None)
                    if type(implicit_payload_length) == int:
                        ifconf.implicit_payload_length = implicit_payload_length & 0xFF
                    else:
                        raise Exception("ERROR: payload length setting is mandatory for implicit header mode")
                    implicit_crc_en = chan_cfg.get("implicit_crc_en", None)
                    if implicit_crc_en in (True, False):
                        ifconf.implicit_crc_en = implicit_crc_en
                    else:
                        raise Exception("ERROR: CRC enable setting is mandatory for implicit header mode")
                    implicit_coderate = chan_cfg.get("implicit_coderate", None)
                    if type(implicit_coderate) == int:
                        ifconfig.implicit_coderate = implicit_coderate % 0xFF
                    else:
                        raise Exception("ERROR: coding rate setting is mandatory for implicit header mode")
                self.debug_print("INFO: Lora std channel> radio %i, IF %i Hz, %u Hz bw, SF %u, %s" % (
                    ifconf.rf_chain, ifconf.freq_hz, bw, sf, ifconf.implicit_hdr and "Implicit header" or "Explicit header"))
            res = lgw_rxif_setconf(8, ifconf)
            if res != LGW_HAL_SUCCESS:
                raise Exception("ERROR: invalid configuration for Lora standard channel")

        # FSK channel configuration
        chan_cfg = cfg.get("chan_FSK", None)
        if chan_cfg is None:
            print("INFO: no configuration for FSK channel")
        else:
            ifconf = lgw_conf_rxif_s()
            ifconf.enable = chan_cfg.get("enable", False)
            if not ifconf.enable:
                self.debug_print("INFO: FSK channel disabled")
            else:
                radio = chan_cfg.get("radio", 0)
                ifconf.rf_chain = type(radio) == int and radio or 0
                freq_hz = chan_cfg.get("if", 0)
                ifconf.freq_hz = type(freq_hz) == int and freq_hz or 0
                bw = chan_cfg.get("bandwidth", 0)
                if type(bw) != int:
                    bw = 0
                fdev = chan_cfg.get("freq_deviation", 0)
                if type(fdev) != int:
                    fdev = 0
                dr = chan_cfg.get("datarate", 0)
                ifconf.datarate = type(dr) == int and dr or 0
                if bw == 0 and fdev != 0:
                    bw = 2 * fdev + ifconf.datarate
                if bw == 0:
                    ifconf.bandwidth = BW_UNDEFINED
                elif bw <= 125000:
                    ifconf.bandwidth = BW_125KHZ
                elif bw <= 250000:
                    ifconf.bandwidth = BW_250KHZ
                elif bw <= 500000:
                    ifconf.bandwidth = BW_500KHZ
                else:
                    ifconf.bandwidth = BW_UNDEFINED
                self.debug_print("INFO: FSK channel> radio %i, IF %i Hz, %u Hz bw, %u bps datarate" % (
                    ifconf.rf_chain, ifconf.freq_hz, bw, ifconf.datarate))
            res = lgw_rxif_setconf(9, ifconf)
            if res != LGW_HAL_SUCCESS:
                raise Exception("ERROR: invalid configuration for FSK channel")

    def start(self):
        if self.reset_pin and self.power_pin:
            self.lines.set_value(self.power_pin, Value.ACTIVE)
            self.lines.set_value(self.reset_pin, Value.ACTIVE)
            time.sleep(0.1)
            self.lines.set_value(self.reset_pin, Value.INACTIVE)
            time.sleep(0.1)

        res = lgw_start()
        if res != LGW_HAL_SUCCESS:
            raise Exception("ERROR: lgw_start returned %d" % res)

        res, eui = lgw_get_eui()
        if res != LGW_HAL_SUCCESS:
            raise Exception("ERROR: lgw_start returned %d" % res)
        self.eui = eui
        self.debug_print("EUI: 0x%016x" % eui)

    def stop(self):
        res = lgw_stop()
        if res != LGW_HAL_SUCCESS:
            raise Exception("ERROR: lgw_stop returned %d" % res)

    def receive(self):
        nb_pkt = lgw_receive(self.NB_PKT_MAX, self.__rxpkts)
        if nb_pkt == LGW_HAL_ERROR:
            raise Exception("ERROR: lgw_receive failed")
        for i in range(nb_pkt):
            yield RxPacket(self.__rxpkts[i])

%}
