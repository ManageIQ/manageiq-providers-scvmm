describe ManageIQ::Providers::Microsoft::InfraManager do
  it ".ems_type" do
    expect(described_class.ems_type).to eq('scvmm')
  end

  it ".description" do
    expect(described_class.description).to eq('Microsoft System Center VMM')
  end

  it ".auth_url handles ipv6" do
    expect(described_class.auth_url("::1")).to eq("http://[::1]:5985/wsman")
  end

  context "#connect with ssl" do
    before do
      @e = FactoryBot.create(:ems_microsoft, :hostname => "host", :security_protocol => "ssl", :ipaddress => "127.0.0.1")
      @e.authentications << FactoryBot.create(:authentication, :userid => "user", :password => "pass")
    end

    it "defaults" do
      expect(described_class).to receive(:raw_connect) do |connection|
        expect(connection[:endpoint]).to match("http://host:5985/wsman")
        expect(connection[:disable_sspi]).to eq(true)
        expect(connection[:user]).to eq("user")
        expect(connection[:password]).to eq("pass")
      end

      @e.connect
    end

    it "accepts overrides" do
      expect(described_class).to receive(:raw_connect) do |connection|
        expect(connection[:endpoint]).to match("http://host2:5985/wsman")
        expect(connection[:disable_sspi]).to eq(true)
        expect(connection[:user]).to eq("user2")
        expect(connection[:password]).to eq("pass2")
      end

      @e.connect(:user => "user2", :password => "pass2", :hostname => "host2")
    end
  end

  context "#connect with kerberos" do
    before do
      @e = FactoryBot.create(:ems_microsoft, :hostname => "host", :security_protocol => "kerberos", :realm => "pretendrealm", :ipaddress => "127.0.0.1")
      @e.authentications << FactoryBot.create(:authentication, :userid => "user", :password => "pass")
    end

    it "defaults" do
      expect(described_class).to receive(:raw_connect) do |connection|
        expect(connection[:endpoint]).to match("http://host:5985/wsman")
        expect(connection[:disable_sspi]).to eq(false)
        expect(connection[:basic_auth_only]).to eq(false)
        expect(connection[:user]).to eq("user")
        expect(connection[:password]).to eq("pass")
        expect(connection[:realm]).to eq("pretendrealm")
      end

      @e.connect
    end

    it "accepts overrides" do
      expect(described_class).to receive(:raw_connect) do |connection|
        expect(connection[:endpoint]).to match("http://host2:5985/wsman")
        expect(connection[:disable_sspi]).to eq(false)
        expect(connection[:basic_auth_only]).to eq(false)
        expect(connection[:user]).to eq("user2")
        expect(connection[:password]).to eq("pass2")
        expect(connection[:realm]).to eq("pretendrealm")
      end

      @e.connect(:user => "user2", :password => "pass2", :hostname => "host2")
    end
  end

  context "#raw_connect with validation" do
    it "validates the connection if validate is true" do
      response = double(:winrm_output)
      output = "{\"ems\":{\"Guid\":\"a2b45b8b-ff0e-425c-baf7-24626963a27c\",\"Version\":\"2.1.0\"}}"
      allow(response).to receive(:stdout).and_return(output)

      allow(ManageIQ::Providers::Microsoft::InfraManager).to receive(:run_powershell_script).and_return(response)

      params = { :endpoint => "http://host2:5985/wsman", :user => "user", :password => "password" }
      described_class.raw_connect(params, true)
    end

    it "raises an exception if validation fails" do
      response = double(:winrm_output)
      output = "{\"ems\":null}"
      error = "FAILURE\r\nMULTILINE FAILURE"
      allow(response).to receive(:stdout).and_return(output)
      allow(response).to receive(:stderr).and_return(error)

      allow(ManageIQ::Providers::Microsoft::InfraManager).to receive(:run_powershell_script).and_return(response)

      params = { :endpoint => "http://host2:5985/wsman", :user => "user", :password => "password" }
      expect { described_class.raw_connect(params, true) }.to raise_exception(MiqException::MiqHostError, "Unable to connect: FAILURE")
    end

    it "decrypts the password" do
      password = MiqPassword.encrypt("password")
      params = { :endpoint => "http://host2:5985/wsman", :user => "user", :password => password }

      expect(MiqPassword).to receive(:try_decrypt).with(password).and_return("password")

      described_class.raw_connect(params)
    end
  end

  context 'catalog types' do
    let(:ems) { FactoryBot.create(:ems_microsoft) }

    it "#supported_catalog_types" do
      expect(ems.supported_catalog_types).to eq(%w(microsoft))
    end
  end
end
