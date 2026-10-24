module PhomemoThermalPrinter
  module Darwin
    class Link < BLE
      def initialize(sink)
        super(:central)
        @phomemo_sink = sink
      end

      def advertising_report_callback(report)
        @phomemo_sink.on_report(report)
      end

      def packet_callback(event_packet)
        super
        @phomemo_sink.on_packet(event_packet)
      end
    end

    class Transport
      CCCD_NOTIFY = "\x01\x00"
      LOOP_TIMEOUT_MS = 600_000
      STEP_MS = 20

      def initialize
        @link = Link.new(self)
        @loop = nil
        reset
      end

      def connect(name_prefix, timeout_ms)
        reset
        @name_prefix = name_prefix
        link = @link
        @loop = Task.new { link.scan(timeout_ms: LOOP_TIMEOUT_MS, stop_state: :no_stop) }
        deadline = Machine.board_millis + timeout_ms
        while !linked? && Machine.board_millis < deadline
          sleep_ms(STEP_MS)
        end
        return true if linked?
        stop_loop
        false
      end

      def on_report(report)
        return if @reported
        return unless Packet.name_matches?(report.reports, @name_prefix)
        @reported = true
        @link.connect(report)
      end

      def on_packet(event_packet)
        handle = Packet.connection_handle(event_packet)
        @handle = handle if handle
        if Packet.disconnect?(event_packet)
          @lost = true
          @handle = nil
        end
        note = Packet.notification(event_packet)
        @inbox << note[1] if note
      end

      def gatt_report
        report = Packet.gatt_report(@link.services)
        @write_handle = report["write_handle"]
        @cccd_handle = report["cccd_handle"]
        {"service" => report["service"], "write" => report["write"], "notify" => report["notify"]}
      end

      def subscribe(settle_ms)
        return false if @lost || @cccd_handle.nil?
        @link.write_characteristic_descriptor_using_descriptor_handle(@handle, @cccd_handle, CCCD_NOTIFY)
        sleep_ms(settle_ms)
        true
      end

      def write_chunk(bytes)
        @link.write_value_of_characteristic_without_response(@handle, @write_handle, bytes)
        nil
      end

      def poll_notifications
        return nil if @lost && @inbox.empty?
        out = @inbox
        @inbox = []
        out
      end

      def disconnect
        stop_loop
        nil
      end

      private

      def linked?
        !@handle.nil? && !@lost && @link.state == :TC_IDLE
      end

      def stop_loop
        return unless @loop
        @loop.terminate
        @loop = nil
        @link.hci_power_control(BLE::HCI_POWER_OFF)
      end

      def reset
        @name_prefix = nil
        @reported = false
        @handle = nil
        @lost = false
        @inbox = []
        @write_handle = nil
        @cccd_handle = nil
      end
    end
  end
end
