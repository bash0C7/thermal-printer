#include <stdint.h>
#include "mruby.h"

int ble_gap_security_initiate(uint16_t conn_handle);

static mrb_value
mrb_s_initiate(mrb_state *mrb, mrb_value klass)
{
  mrb_int conn_handle;
  mrb_get_args(mrb, "i", &conn_handle);
  return mrb_int_value(mrb, ble_gap_security_initiate((uint16_t)conn_handle));
}

void
mrb_dualkey_pairing_gem_init(mrb_state *mrb)
{
  struct RClass *mod = mrb_define_module(mrb, "DualKeyPairing");
  mrb_define_class_method(mrb, mod, "initiate", mrb_s_initiate, MRB_ARGS_REQ(1));
}

void
mrb_dualkey_pairing_gem_final(mrb_state *mrb)
{
}
