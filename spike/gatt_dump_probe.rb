require "env"
require "ble"

class GattDumpProbe < BLE
  BASE_TAIL = "\x00\x00\x10\x00\x80\x00\x00\x80\x5F\x9B\x34\xFB"
  PROP_NAMES = { 0x01 => "broadcast", 0x02 => "read", 0x04 => "write_no_rsp", 0x08 => "write",
                 0x10 => "notify", 0x20 => "indicate", 0x40 => "signed_write", 0x80 => "ext" }

  def initialize(log, prefix)
    super(:central)
    @log = log
    @prefix = prefix
    @target = nil
    @notifications = 0
    @disconnected = false
    @t0 = Machine.board_millis
  end

  def emit(line)
    stamp = Machine.board_millis - @t0
    text = "[+#{stamp}ms] #{line}"
    puts text
    f = File.open(@log, "a")
    f.puts text
    f.close
  end

  def hex(value)
    return "(nil)" if value.nil?
    out = []
    i = 0
    while i < value.bytesize
      out << sprintf("%02x", value.getbyte(i))
      i += 1
    end
    out.join(" ")
  end

  def uuid_str(u)
    h = hex(u).delete(" ")
    "#{h[0, 8]}-#{h[8, 4]}-#{h[12, 4]}-#{h[16, 4]}-#{h[20, 12]}"
  end

  def uuid128_for(uuid16)
    "\x00\x00" + [(uuid16 >> 8) & 0xff, uuid16 & 0xff].pack("CC") + BASE_TAIL
  end

  def props_str(p)
    names = []
    PROP_NAMES.each { |bit, name| names << name if (p & bit) != 0 }
    "0x#{p.to_s(16)}(#{names.join(',')})"
  end

  def advertising_report_callback(report)
    return if @target
    name = report.reports[:complete_local_name] || report.reports[:shortened_local_name] || ""
    return unless name.start_with?(@prefix)
    @target = report
    emit("target name=#{name.inspect} addr=#{BLE::Utils.bd_addr_to_str(report.address)} rssi=#{report.rssi}")
    emit("adv reports:\n#{report.format}")
    connect(report)
  end

  def pop_and_dispatch
    _event_popped
    event = @event_queue.pop(timeout_ms: 0)
    return nil unless event
    packet_callback(event) if event.is_a?(String)
    event
  end

  def packet_callback(event_packet)
    type = event_packet.getbyte(0)
    if type == HCI_EVENT_DISCONNECTION_COMPLETE || (type == HCI_EVENT_LE_META && event_packet.getbyte(2) == HCI_EVENT_DISCONNECTION_COMPLETE)
      @disconnected = true
      @conn_handle = HCI_CON_HANDLE_INVALID
      emit("disconnect packet #{hex(event_packet)}")
    end
    super
    if type == GATT_EVENT_NOTIFICATION
      @notifications += 1
      emit("notify##{@notifications} handle=#{gatt_event_int16(event_packet, 0)} value=#{hex(gatt_event_value(event_packet))}")
    end
  end

  def drain(ms)
    until_ms = Machine.board_millis + ms
    while Machine.board_millis < until_ms
      pop_and_dispatch
      sleep_ms(20)
    end
  end

  def find_by_uuid(list, uuid16)
    want = uuid128_for(uuid16)
    found = nil
    list.each { |e| found = e if e[:uuid128] == want }
    found
  end

  def dump_services
    emit("services=#{services.size}")
    services.each do |s|
      emit("service #{uuid_str(s[:uuid128])} handles=#{s[:start_handle]}..#{s[:end_handle]} chars=#{s[:characteristics].size}")
      s[:characteristics].each do |c|
        emit("  char #{uuid_str(c[:uuid128])} vh=#{c[:value_handle]} props=#{props_str(c[:properties])} value=#{hex(c[:value])}")
        c[:descriptors].each do |d|
          emit("    desc #{uuid_str(d[:uuid128])} handle=#{d[:handle]} value=#{hex(d[:value])}")
        end
      end
    end
  end

  def subscribe_ff03
    svc = find_by_uuid(services, 0xff00)
    unless svc
      emit("RESULT ff00 service: absent")
      return
    end
    emit("RESULT ff00 service: present")
    ff02 = find_by_uuid(svc[:characteristics], 0xff02)
    ff03 = find_by_uuid(svc[:characteristics], 0xff03)
    emit("RESULT ff02: #{ff02 ? 'present props=' + props_str(ff02[:properties]) : 'absent'}")
    emit("RESULT ff03: #{ff03 ? 'present props=' + props_str(ff03[:properties]) : 'absent'}")
    return unless ff03
    cccd = find_by_uuid(ff03[:descriptors], 0x2902)
    unless cccd
      emit("RESULT ff03 CCCD: absent descriptors=#{ff03[:descriptors].inspect}")
      return
    end
    emit("drain before subscribe (300ms)")
    drain(300)
    emit("write CCCD handle=#{cccd[:handle]} value=01 00 (only write in this probe)")
    rc = write_characteristic_descriptor_using_descriptor_handle(@conn_handle, cccd[:handle], "\x01\x00")
    emit("CCCD write rc=#{rc}")
    drain(5000)
    emit("RESULT notifications after subscribe=#{@notifications} disconnected=#{@disconnected}")
  end

  def run(timeout_ms)
    emit("probe start prefix=#{@prefix} scan_timeout_ms=#{timeout_ms}")
    scan(timeout_ms: timeout_ms, stop_state: :TC_IDLE)
    unless @target
      emit("RESULT T02 not found (power on the printer, disconnect other clients, re-run)")
      return 3
    end
    if @conn_handle == HCI_CON_HANDLE_INVALID
      emit("RESULT target found but connection failed")
      return 4
    end
    emit("connected handle=#{@conn_handle}")
    dump_services
    subscribe_ff03
    0
  end
end

log = ARGV[0] || "/Users/bash/dev/src/github.com/bash0C7/thermal-printer/build/logs/gatt-dump.log"
timeout_ms = (ARGV[1] || "20000").to_i
prefix = ARGV[2] || "T02"

probe = GattDumpProbe.new(log, prefix)
exit(probe.run(timeout_ms))
