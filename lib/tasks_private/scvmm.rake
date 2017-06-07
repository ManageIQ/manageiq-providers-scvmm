require 'winrm'
require 'json'
require 'yaml'

namespace :manageiq do
  namespace :providers do
    namespace :scvmm do
      desc "Create a JSON output file used for specs"
      task :generate_json, [:username, :password, :host, :port] do |_t, args|
        secrets = Rails.application.secrets.scvmm

        host     = args[:host]     || secrets['host']
        port     = args[:port]     || secrets['port']
        username = args[:username] || secrets['username']
        password = args[:password] || secrets['password']

        provider_root = ManageIQ::Providers::Scvmm::Engine.root.to_s

        ps_script = File.join(
          provider_root,
          'app/models/manageiq/providers/microsoft/infra_manager/ps_scripts',
          'get_inventory.ps1'
        )

        endpoint = "http://#{host}:#{port}/wsman"

        winrm = WinRM::Connection.new(
          :endpoint     => endpoint,
          :user         => username,
          :password     => password,
          :disable_sspi => true
        )

        output_json = File.join(
          provider_root,
          'spec/tools/scvmm_data/get_inventory_output.json'
        )

        begin
          shell = winrm.shell(:powershell)
          output = shell.run(IO.read(ps_script))
          if output.stderr && output.stderr != ''
            raise "Inventory collection failed: " + output.stderr
          else
            File.open(output_json, 'w') { |fh| fh.write output.stdout }
          end
        ensure
          shell.close
        end
      end
    end
  end
end
