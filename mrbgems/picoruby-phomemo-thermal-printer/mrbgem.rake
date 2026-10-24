MRuby::Gem::Specification.new('picoruby-phomemo-thermal-printer') do |spec|
  spec.license = 'MIT'
  spec.author  = 'bash0C7'
  spec.summary = 'Phomemo T02 thermal printer over BLE'
  spec.require_name = 'phomemo_thermal_printer'
  spec.add_dependency 'picoruby-ble'
  spec.rbfiles.concat(Dir.glob("#{dir}/ports/darwin/*.rb").sort) if build.darwin?
end
