%module loragw

%include typemaps.i
%include "stdint.i"
%include "carrays.i"
%include "cdata.i"

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
