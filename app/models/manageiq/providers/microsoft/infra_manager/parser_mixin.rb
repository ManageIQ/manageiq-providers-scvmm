module ManageIQ::Providers::Microsoft::InfraManager::ParserMixin
  # Get the first IPAddress from the first Network Adapter where the
  # UsedForManagement property is true.
  #
  def identify_primary_ip(host)
    prefix    = "MIQ(#{self.class.name})##{__method__})"
    switches  = host['VirtualSwitch']
    adapters  = switches.collect { |s| s['VMHostNetworkAdapters'] }.flatten
    host_name = host['Name']

    if switches.blank? || adapters.blank?
      $scvmm_log.warn("#{prefix} Found no management IP for #{host_name}. Setting IP to nil")
      return nil
    end

    adapter = adapters.find { |e| e['UsedForManagement'] }

    if adapter.blank?
      $scvmm_log.warn("#{prefix} Found no management IP for #{host_name}. Setting IP to nil")
      nil
    else
      adapter['IPAddresses'].split.first # Avoid IPv6 text if present
    end
  end

  def lookup_overall_state(overall_state)
    # OverallState enum:
    # 0 => Ok
    # 2 => Needs Attention
    # 8 => In Maintenance Mode
    overall_state == 8
  end

  def lookup_power_state(power_state_input)
    case power_state_input
    when "Running"         then "on"
    when "Paused", "Saved" then "suspended"
    when "PowerOff"        then "off"
    else "unknown"
    end
  end

  def lookup_connected_state(connected_state_input)
    case connected_state_input
    when "true", "Responding"
      "connected"
    when "false", "NotResponding", "AccessDenied", "NoConnection"
      "disconnected"
    else
      "unknown"
    end
  end

  def lookup_disk_type(disk)
    # TODO: Add A New Type In Database For Differencing
    case disk['VHDType']
    when "DynamicallyExpanding", "Expandable", "Differencing", 1, 3
      "thin"
    when "Fixed", 0, 2
      "thick"
    else
      "unknown"
    end
  end

  def convert_windows_date_string_to_ruby_time(string)
    seconds = string[/Date\((.*?)\)/, 1].to_i
    Time.at(seconds / 1000).utc
  end

  def path_to_uri(file, hostname = nil)
    file = Addressable::URI.encode(file.tr('\\', '/'))
    hostname = URI::Generic.build(:host => hostname).host if hostname # ensure IPv6 hostnames
    "file://#{hostname}/#{file}"
  end

  def host_platform_unsupported?(host_hash)
    %w(vmwareesx).include?(host_hash["VirtualizationPlatformString"])
  end

  def process_vm_os_description(vm)
    if vm['OperatingSystem']['Name'].casecmp('unknown').zero?
      "Unknown"
    else
      vm['OperatingSystem']['Description']
    end
  end

  def process_cidr(string)
    if string && string.include?('.')
      string[/(.*?\/\d+)/, 1]
    else
      nil
    end
  end

  def process_computer_name(computername)
    return if computername.nil?
    log_header = "MIQ(#{self.class.name}.#{__method__})"

    if computername.start_with?("getaddrinfo failed_")
      $scvmm_log.warn("#{log_header} Invalid hostname value returned from SCVMM: #{computername}")
      "Unavailable"
    else
      computername
    end
  end
end
