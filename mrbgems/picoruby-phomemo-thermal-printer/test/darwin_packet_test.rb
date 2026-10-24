class DarwinPacketTest < Picotest::Test
  def pk
    PhomemoThermalPrinter::Darwin::Packet
  end

  def bytes(*list)
    list.pack("C*")
  end

  def notify_packet(handle, value)
    len = value.bytesize
    bytes(0xA7, 12 + len, 0, 0, 0, 0, 0, 0, handle & 0xff, handle >> 8, len & 0xff, len >> 8) + value
  end

  def ff_uuid(short)
    bytes(0x00, 0x00, short >> 8, short & 0xff, 0x00, 0x00, 0x10, 0x00, 0x80, 0x00, 0x00, 0x80, 0x5f, 0x9b, 0x34, 0xfb)
  end

  def phomemo_services
    [
      {
        start_handle: 1, end_handle: 8, uuid128: ff_uuid(0xff00),
        characteristics: [
          {value_handle: 3, properties: 0x02, uuid128: ff_uuid(0xff01), descriptors: []},
          {value_handle: 5, properties: 0x0c, uuid128: ff_uuid(0xff02), descriptors: []},
          {value_handle: 7, properties: 0x10, uuid128: ff_uuid(0xff03),
           descriptors: [{handle: 8, uuid128: ff_uuid(0x2902)}]}
        ]
      }
    ]
  end

  def funny_print_services
    [
      {
        start_handle: 1, end_handle: 8, uuid128: ff_uuid(0xffe6),
        characteristics: [
          {value_handle: 3, properties: 0x0c, uuid128: ff_uuid(0xffe1), descriptors: []},
          {value_handle: 5, properties: 0x10, uuid128: ff_uuid(0xffe2),
           descriptors: [{handle: 6, uuid128: ff_uuid(0x2902)}]}
        ]
      }
    ]
  end

  def test_darwin_disconnect_shape_is_detected
    assert pk.disconnect?(bytes(0x3E, 0x01, 0x05))
  end

  def test_btstack_and_esp32_disconnect_shape_is_detected
    assert pk.disconnect?(bytes(0x05, 4, 0x40, 0x00, 0x00, 0x13))
  end

  def test_connection_complete_is_not_a_disconnect
    assert_false pk.disconnect?(bytes(0x3E, 0x01, 0x01, 0x00, 0x40, 0x00))
  end

  def test_connection_complete_yields_the_little_endian_connection_handle
    assert_equal 0x0140, pk.connection_handle(bytes(0x3E, 0x01, 0x01, 0x00, 0x40, 0x01))
  end

  def test_failed_connection_complete_has_no_handle
    assert_equal nil, pk.connection_handle(bytes(0x3E, 0x01, 0x01, 0x3e, 0x40, 0x00))
  end

  def test_other_packets_have_no_connection_handle
    assert_equal nil, pk.connection_handle(bytes(0x3E, 0x01, 0x05, 0x00, 0x40, 0x00))
    assert_equal nil, pk.connection_handle(notify_packet(7, bytes(0x01, 0x01)))
    assert_equal nil, pk.connection_handle(bytes(0x3E, 0x01, 0x01))
    assert_equal nil, pk.connection_handle("")
  end

  def test_notification_packet_is_not_a_disconnect
    assert_false pk.disconnect?(notify_packet(7, bytes(0x01, 0x01)))
  end

  def test_empty_and_short_packets_are_not_a_disconnect
    assert_false pk.disconnect?("")
    assert_false pk.disconnect?(bytes(0x3E, 0x01))
  end

  def test_notification_packet_yields_handle_and_value
    value = bytes(0x1a, 0x06, 0x89)
    assert_equal [0x2a, value], pk.notification(notify_packet(0x2a, value))
  end

  def test_observed_acknowledge_notify_yields_handle_7
    value = bytes(0x01, 0x01)
    assert_equal [7, value], pk.notification(notify_packet(7, value))
  end

  def test_observed_max_write_notify_yields_three_bytes
    value = bytes(0x02, 0xb6, 0x00)
    assert_equal [7, value], pk.notification(notify_packet(7, value))
  end

  def test_observed_unknown_notify_keeps_every_byte
    value = bytes(0x1a, 0x3b, 0x04, 0x40, 0x00, 0x00, 0x00)
    assert_equal [7, value], pk.notification(notify_packet(7, value))
  end

  def test_value_is_cut_at_the_declared_length
    value = bytes(0x01, 0x01)
    pkt = notify_packet(7, value) + bytes(0xee, 0xee)
    assert_equal [7, value], pk.notification(pkt)
  end

  def test_255_byte_value_is_returned_whole
    value = ("a" * 255)
    result = pk.notification(notify_packet(9, value))
    assert_equal 9, result[0]
    assert_equal 255, result[1].bytesize
  end

  def test_truncated_notification_packet_is_nil
    assert_nil pk.notification(bytes(0xA7, 8, 0, 0, 0, 0, 0, 0))
  end

  def test_non_notification_packet_is_nil
    assert_nil pk.notification(bytes(0xA0, 0))
  end

  def test_empty_packet_is_nil
    assert_nil pk.notification("")
  end

  def test_name_is_matched_by_prefix_not_substring
    assert pk.name_matches?({complete_local_name: "T02"}, "T02")
    assert pk.name_matches?({complete_local_name: "T02E"}, "T02")
    assert_false pk.name_matches?({complete_local_name: "MyT02"}, "T02")
    assert_false pk.name_matches?({}, "T02")
  end

  def test_shortened_local_name_is_matched_by_prefix
    assert pk.name_matches?({shortened_local_name: "T02"}, "T02")
    assert_false pk.name_matches?({shortened_local_name: "XT02"}, "T02")
  end

  def test_observed_advertisement_matches_t02
    reports = {complete_local_name: "T02", manufacturer_specific_data: bytes(0x00, 0x00, 0xE8, 0x0B, 0xB3, 0x0F, 0x90, 0x6C)}
    assert pk.name_matches?(reports, "T02")
  end

  def test_advertisement_without_a_name_does_not_match
    assert_false pk.name_matches?({manufacturer_specific_data: bytes(0x00, 0x00)}, "T02")
  end

  def test_name_shorter_than_prefix_does_not_match
    assert_false pk.name_matches?({complete_local_name: "T0"}, "T02")
  end

  def test_uuid128_for_is_the_canonical_big_endian_form
    assert_equal ff_uuid(0xff00), pk.uuid128_for(0xff00)
    assert_equal ff_uuid(0x2902), pk.uuid128_for(0x2902)
    assert_equal 16, pk.uuid128_for(0xff03).bytesize
  end

  def test_phomemo_gatt_is_ready
    r = pk.gatt_report(phomemo_services)
    assert_equal true, r["service"]
    assert_equal true, r["write"]
    assert_equal true, r["notify"]
  end

  def test_phomemo_gatt_yields_the_observed_handles
    r = pk.gatt_report(phomemo_services)
    assert_equal 5, r["write_handle"]
    assert_equal 8, r["cccd_handle"]
  end

  def test_funny_print_lx_named_t02_is_not_ready
    r = pk.gatt_report(funny_print_services)
    assert_equal false, r["service"]
    assert_equal false, r["write"]
    assert_equal false, r["notify"]
    assert_nil r["write_handle"]
    assert_nil r["cccd_handle"]
  end

  def test_no_services_is_not_ready
    r = pk.gatt_report([])
    assert_equal false, r["service"]
    assert_equal false, r["write"]
    assert_equal false, r["notify"]
  end

  def test_write_without_response_is_required_for_write
    services = phomemo_services
    services[0][:characteristics][1][:properties] = 0x08
    r = pk.gatt_report(services)
    assert_equal true, r["service"]
    assert_equal false, r["write"]
  end

  def test_notify_property_is_required_for_notify
    services = phomemo_services
    services[0][:characteristics][2][:properties] = 0x02
    r = pk.gatt_report(services)
    assert_equal false, r["notify"]
  end

  def test_notify_without_cccd_descriptor_has_no_cccd_handle
    services = phomemo_services
    services[0][:characteristics][2][:descriptors] = []
    r = pk.gatt_report(services)
    assert_nil r["cccd_handle"]
  end

  def test_characteristics_outside_the_ff00_service_are_ignored
    services = funny_print_services
    services[0][:characteristics][0][:uuid128] = ff_uuid(0xff02)
    r = pk.gatt_report(services)
    assert_equal false, r["service"]
    assert_equal false, r["write"]
  end
end
