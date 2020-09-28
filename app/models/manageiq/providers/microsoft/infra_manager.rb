class ManageIQ::Providers::Microsoft::InfraManager < ManageIQ::Providers::InfraManager
  require_nested :Cluster
  require_nested :Datacenter
  require_nested :Folder
  require_nested :Host
  require_nested :Provision
  require_nested :ProvisionWorkflow
  require_nested :Refresher
  require_nested :RefreshWorker
  require_nested :ResourcePool
  require_nested :Storage
  require_nested :Subnet
  require_nested :Template
  require_nested :Vm

  include_concern "Powershell"

  supports :provisioning

  def self.ems_type
    @ems_type ||= "scvmm".freeze
  end

  def self.description
    @description ||= "Microsoft System Center VMM".freeze
  end

  def self.params_for_create
    @params_for_create ||= {
      :title  => "Configure #{description}",
      :fields => [
        {
          :component => 'sub-form',
          :id        => 'endpoints-subform',
          :name      => 'endpoints-subform',
          :title     => _("Endpoints"),
          :fields    => [{
            :component              => 'validate-provider-credentials',
            :id                     => 'endpoints.default.valid',
            :name                   => 'endpoints.default.valid',
            :skipSubmit             => true,
            :isRequired             => true,
            :validationDependencies => %w[type zone_id],
            :fields                 => [
              {
                :component  => "text-field",
                :id         => "endpoints.default.hostname",
                :name       => "endpoints.default.hostname",
                :label      => _("Hostname (or IPv4 or IPv6 address)"),
                :isRequired => true,
                :validate   => [{:type => "required"}]
              },
              {
                :component  => "select",
                :id         => "endpoints.default.security_protocol",
                :name       => "endpoints.default.security_protocol",
                :label      => _("Security Protocol"),
                :isRequired => true,
                :validate   => [{:type => "required"}],
                :options    => [
                  {
                    :label => _("SSL"),
                    :value => "ssl",
                  },
                  {
                    :label => _("Kerberos"),
                    :value => "kerberos",
                  }
                ]
              },
              {
                :component  => "text-field",
                :id         => "realm",
                :name       => "realm",
                :label      => _("Realm"),
                :isRequired => true,
                :validate   => [{:type => "required"}],
                :helperText => _('Username must be in the format: name@realm'),
                :condition  => {
                  :when => 'endpoints.default.security_protocol',
                  :is   => 'kerberos',
                },
              },
              {
                :component  => "text-field",
                :id         => "authentications.default.userid",
                :name       => "authentications.default.userid",
                :label      => _("Username"),
                :isRequired => true,
                :helperText => _('Should have privileged access, such as root or administrator.'),
                :validate   => [{:type => "required"}]
              },
              {
                :component  => "password-field",
                :id         => "authentications.default.password",
                :name       => "authentications.default.password",
                :label      => _("Password"),
                :type       => "password",
                :isRequired => true,
                :validate   => [{:type => "required"}]
              },
            ],
          }],
        },
      ]
    }.freeze
  end

  def self.verify_credentials(args)
    realm = args['realm']
    endpoint = args.dig("endpoints", 'default')
    hostname, security_protocol = endpoint&.values_at('hostname', 'security_protocol')
    authentication = args.dig("authentications", "default")
    userid, password = authentication&.values_at('userid', 'password')
    password = MiqPassword.try_decrypt(password)
    password ||= find(args["id"]).authentication_password(authtype) if args['id']

    !raw_connect(build_connect_params(:user              => userid,
                                      :password          => password,
                                      :hostname          => hostname,
                                      :realm             => realm,
                                      :security_protocol => security_protocol), true)
  end

  def self.raw_connect(connect_params, validate = false)
    require 'winrm'

    connect_params[:operation_timeout] ||= 1800
    connect_params[:password] = ManageIQ::Password.try_decrypt(connect_params[:password])

    connect = WinRM::Connection.new(connect_params)
    return connect unless validate

    connection_rescue_block do
      results = run_test_connection_script(connect)
      json = parse_json_results(results.stdout)
      raise results.stderr.split("\r\n").first if json.blank? || json["ems"].blank?
    end
  end

  def self.run_test_connection_script(connection)
    test_connection_script = File.join(File.dirname(__FILE__), 'infra_manager/ps_scripts/test_connection.ps1')
    run_powershell_script(connection, IO.read(test_connection_script))
  end
  private_class_method :run_test_connection_script

  def self.auth_url(hostname, port = nil)
    URI::HTTP.build(:host => hostname, :port => port || 5985, :path => "/wsman").to_s
  end

  def self.build_connect_params(options)
    connect_params  = {
      :user         => options[:user],
      :password     => options[:password],
      :endpoint     => options[:endpoint] || auth_url(options[:hostname], options[:port]),
      :disable_sspi => true
    }

    if options[:security_protocol] == "kerberos"
      connect_params.merge!(
        :realm           => options[:realm],
        :basic_auth_only => false,
        :disable_sspi    => false
      )
    end

    connect_params
  end

  def self.connection_rescue_block(realm = nil)
    require 'winrm'
    require 'gssapi' # A winrm dependency
    yield
  rescue WinRM::WinRMHTTPTransportError => e # Error 401
    raise MiqException::MiqHostError, "Check credentials and WinRM configuration settings. " \
    "Remote error message: #{e.message}"
  rescue GSSAPI::GssApiError
    raise MiqException::MiqHostError, "Unable to reach any KDC in realm #{realm}"
  rescue => e
    raise MiqException::MiqHostError, "Unable to connect: #{e.message}"
  end

  def connect(options = {})
    raise "no credentials defined" if missing_credentials?(options[:auth_type])

    hostname           = options[:hostname] || self.hostname
    options[:endpoint] = self.class.auth_url(hostname, port)
    options[:user]   ||= authentication_userid(options[:auth_type])
    options[:password] = options[:password] || authentication_password(options[:auth_type])

    options[:realm]             = realm
    options[:security_protocol] = security_protocol

    options[:validate] ||= false

    self.class.raw_connect(self.class.build_connect_params(options), options[:validate])
  end

  def verify_credentials(_auth_type = nil, options = {})
    raise MiqException::MiqHostError, "No credentials defined" if missing_credentials?(options[:auth_type])

    self.class.connection_rescue_block do
      connect(:validate => true)
    end

    true
  end

  def self.catalog_types
    {"microsoft" => N_("SCVMM")}
  end

  def vm_start(vm, _options = {})
    case vm.power_state
    when "suspended" then execute_power_operation("Resume", vm.uid_ems)
    when "off"       then execute_power_operation("Start", vm.uid_ems)
    end
  end

  def vm_stop(vm, _options = {})
    execute_power_operation("Stop", vm.uid_ems, "-Force")
  end

  def vm_shutdown_guest(vm, _options = {})
    execute_power_operation("Stop", vm.uid_ems, "-Shutdown")
  end

  def vm_reset(vm, _options = {})
    execute_power_operation("Reset", vm.uid_ems)
  end

  def vm_reboot_guest(vm, _options = {})
    execute_power_operation("Stop", vm.uid_ems, "-Shutdown")
    execute_power_operation("Start", vm.uid_ems)
  end

  def vm_suspend(vm, _options = {})
    execute_power_operation("Suspend", vm.uid_ems)
  end

  def vm_resume(vm, _options = {})
    execute_power_operation("Resume", vm.uid_ems)
  end

  def vm_destroy(vm, _options = {})
    vm_stop(vm)
    execute_power_operation("Remove", vm.uid_ems)
  end

  def vm_create_evm_snapshot(vm, _options)
    log_prefix = "vm_create_evm_snapshot: vm=[#{vm.name}]"

    host_handle = vm.host.host_handle
    host_handle.vm_create_evm_checkpoint(vm.name)
  rescue => err
    $scvmm_log.error "#{log_prefix}, error: #{err}"
    $scvmm_log.debug { err.backtrace.join("\n") }
    raise
  end

  def vm_delete_evm_snapshot(vm, _options)
    log_prefix = "vm_delete_evm_snapshot: vm=[#{vm.name}]"

    host_handle = vm.host.host_handle
    host_handle.vm_remove_evm_checkpoint(vm.name)
  rescue => err
    $scvmm_log.error "#{log_prefix}, error: #{err}"
    $scvmm_log.debug { err.backtrace.join("\n") }
    raise
  end

  def self.display_name(number = 1)
    n_('Infrastructure Provider (Microsoft)', 'Infrastructure Providers (Microsoft)', number)
  end

  private

  def execute_power_operation(cmdlet, vm_uid_ems, *parameters)
    return unless vm_uid_ems.guid?

    params  = parameters.join(" ")

    # TODO: If localhost could feasibly be changed to an IPv6 address such as "::1", we need to
    # wrap the IPv6 address in square brackets,  similar to the a URIs's host field, "[::1]".
    command = "powershell Import-Module VirtualMachineManager; Get-SCVMMServer localhost;\
      #{cmdlet}-SCVirtualMachine -VM (Get-SCVirtualMachine -ID #{vm_uid_ems}) #{params}"
    run_dos_command(command)
  end
end
