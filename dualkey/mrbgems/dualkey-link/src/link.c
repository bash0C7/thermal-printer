#include <stdint.h>
#include "mruby.h"

int ble_gap_security_initiate(uint16_t conn_handle);
int ble_gattc_exchange_mtu(uint16_t conn_handle, void *cb, void *cb_arg);
uint16_t ble_att_mtu(uint16_t conn_handle);
int ble_gap_terminate(uint16_t conn_handle, uint8_t hci_reason);
void ble_store_config_init(void);

static int store_ready = 0;

static mrb_value
mrb_s_pair(mrb_state *mrb, mrb_value klass)
{
  mrb_int conn_handle;
  mrb_get_args(mrb, "i", &conn_handle);
  if (!store_ready) {
    ble_store_config_init();
    store_ready = 1;
  }
  return mrb_int_value(mrb, ble_gap_security_initiate((uint16_t)conn_handle));
}

static mrb_value
mrb_s_exchange_mtu(mrb_state *mrb, mrb_value klass)
{
  mrb_int conn_handle;
  mrb_get_args(mrb, "i", &conn_handle);
  return mrb_int_value(mrb, ble_gattc_exchange_mtu((uint16_t)conn_handle, NULL, NULL));
}

static mrb_value
mrb_s_mtu(mrb_state *mrb, mrb_value klass)
{
  mrb_int conn_handle;
  mrb_get_args(mrb, "i", &conn_handle);
  return mrb_int_value(mrb, ble_att_mtu((uint16_t)conn_handle));
}

static mrb_value
mrb_s_disconnect(mrb_state *mrb, mrb_value klass)
{
  mrb_int conn_handle;
  mrb_get_args(mrb, "i", &conn_handle);
  return mrb_int_value(mrb, ble_gap_terminate((uint16_t)conn_handle, 0x13));
}

void
mrb_dualkey_link_gem_init(mrb_state *mrb)
{
  struct RClass *mod = mrb_define_module(mrb, "DualKeyLink");
  mrb_define_class_method(mrb, mod, "pair", mrb_s_pair, MRB_ARGS_REQ(1));
  mrb_define_class_method(mrb, mod, "exchange_mtu", mrb_s_exchange_mtu, MRB_ARGS_REQ(1));
  mrb_define_class_method(mrb, mod, "mtu", mrb_s_mtu, MRB_ARGS_REQ(1));
  mrb_define_class_method(mrb, mod, "disconnect", mrb_s_disconnect, MRB_ARGS_REQ(1));
}

void
mrb_dualkey_link_gem_final(mrb_state *mrb)
{
}
