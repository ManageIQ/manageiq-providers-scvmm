require 'winrm'
require 'json'
require 'yaml'

namespace :manageiq do
  namespace :providers do
    namespace :scvmm do
      desc "Regenerate VCR cassette"
      task :regenerate_cassette, [:username, :password, :host, :port] do |_t, args|
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

        output_yml = File.join(
          provider_root,
          'spec/tools/scvmm_data/get_inventory_output.yml'
        )

        begin
          shell = winrm.shell(:powershell)
          output = shell.run(IO.read(ps_script))
          if output.stderr && output.stderr != ''
            raise "Inventory collection failed: " + output.stderr
          else
            data = JSON.parse(output.stdout)
            File.open(output_yml, 'w') { |fh| fh.write data.to_yaml }
          end
        ensure
          shell.close
        end
      end
    end
  end
end
