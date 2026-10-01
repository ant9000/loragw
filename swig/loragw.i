%module loragw

%include typemaps.i
%include "stdint.i"

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
