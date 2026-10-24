module PhomemoThermalPrinter
  module Darwin
    module Packet
      HCI_EVENT_DISCONNECTION_COMPLETE = 0x05
      HCI_EVENT_LE_META = 0x3E
      HCI_SUBEVENT_LE_CONNECTION_COMPLETE = 0x01
      GATT_EVENT_NOTIFICATION = 0xA7
      NOTIFICATION_HEADER_SIZE = 12
      PROP_WRITE_WITHOUT_RESPONSE = 0x04
      PROP_NOTIFY = 0x10
      PROP_INDICATE = 0x20
      SERVICE_SHORT = 0xff00
      WRITE_SHORT = 0xff02
      NOTIFY_SHORT = 0xff03
      CCCD_SHORT = 0x2902

      def self.disconnect?(pkt)
        type = pkt.getbyte(0)
        return true if type == HCI_EVENT_DISCONNECTION_COMPLETE
        type == HCI_EVENT_LE_META && pkt.getbyte(2) == HCI_EVENT_DISCONNECTION_COMPLETE
      end

      def self.connection_handle(pkt)
        return nil if pkt.bytesize < 6
        return nil unless pkt.getbyte(0) == HCI_EVENT_LE_META
        return nil unless pkt.getbyte(2) == HCI_SUBEVENT_LE_CONNECTION_COMPLETE
        return nil unless pkt.getbyte(3) == 0
        pkt.getbyte(4) | (pkt.getbyte(5) << 8)
      end

      def self.notification(pkt)
        return nil unless pkt.getbyte(0) == GATT_EVENT_NOTIFICATION
        return nil if pkt.bytesize < NOTIFICATION_HEADER_SIZE
        handle = pkt.getbyte(8) | (pkt.getbyte(9) << 8)
        length = pkt.getbyte(10) | (pkt.getbyte(11) << 8)
        return nil if pkt.bytesize < NOTIFICATION_HEADER_SIZE + length
        [handle, pkt.byteslice(NOTIFICATION_HEADER_SIZE, length)]
      end

      def self.name_matches?(reports, prefix)
        return true if starts_with?(reports[:complete_local_name], prefix)
        starts_with?(reports[:shortened_local_name], prefix)
      end

      def self.starts_with?(name, prefix)
        return false unless name
        size = prefix.bytesize
        name.bytesize >= size && name.byteslice(0, size) == prefix
      end

      def self.uuid128_for(short)
        [0x00, 0x00, short >> 8, short & 0xff, 0x00, 0x00, 0x10, 0x00,
         0x80, 0x00, 0x00, 0x80, 0x5f, 0x9b, 0x34, 0xfb].pack("C*")
      end

      def self.gatt_report(services)
        report = {"service" => false, "write" => false, "notify" => false,
                  "write_handle" => nil, "cccd_handle" => nil}
        service = find_service(services, uuid128_for(SERVICE_SHORT))
        return report unless service
        report["service"] = true
        chars = service[:characteristics]
        write = find_characteristic(chars, uuid128_for(WRITE_SHORT))
        if write && (write[:properties] & PROP_WRITE_WITHOUT_RESPONSE) != 0
          report["write"] = true
          report["write_handle"] = write[:value_handle]
        end
        notify = find_characteristic(chars, uuid128_for(NOTIFY_SHORT))
        if notify && (notify[:properties] & (PROP_NOTIFY | PROP_INDICATE)) != 0
          report["notify"] = true
          report["cccd_handle"] = find_descriptor_handle(notify, uuid128_for(CCCD_SHORT))
        end
        report
      end

      def self.find_service(services, uuid128)
        i = 0
        while i < services.size
          return services[i] if services[i][:uuid128] == uuid128
          i += 1
        end
        nil
      end

      def self.find_characteristic(chars, uuid128)
        i = 0
        while i < chars.size
          return chars[i] if chars[i][:uuid128] == uuid128
          i += 1
        end
        nil
      end

      def self.find_descriptor_handle(char, uuid128)
        descriptors = char[:descriptors]
        i = 0
        while i < descriptors.size
          return descriptors[i][:handle] if descriptors[i][:uuid128] == uuid128
          i += 1
        end
        nil
      end
    end
  end
end
