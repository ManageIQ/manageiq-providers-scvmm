describe ManageIQ::Providers::Microsoft::InfraManager::RefreshParser do
  let(:ems)            { FactoryGirl.create(:ems_microsoft).tap { |ems| allow(ems).to receive(:connect) } }
  let(:refresh_parser) { described_class.new(ems) }

  describe '#path_to_uri' do
    it 'is defined and returns a string' do
      expect(refresh_parser.send(:path_to_uri, 'foo')).to be_kind_of(String)
    end

    it 'returns the expected result' do
      expect(refresh_parser.send(:path_to_uri, 'foo')).to eql("file:///foo")
      expect(refresh_parser.send(:path_to_uri, 'foo/bar')).to eql("file:///foo/bar")
      expect(refresh_parser.send(:path_to_uri, 'foo/bar-stuff')).to eql("file:///foo/bar-stuff")
      expect(refresh_parser.send(:path_to_uri, 'foo/C:/bar')).to eql("file:///foo/C:/bar")
      expect(refresh_parser.send(:path_to_uri, 'foo/[bar]')).to eql("file:///foo/%5Bbar%5D")
    end

    it 'accepts an optional hostname and returns the expected result' do
      hostname = 'lab.example.com'

      expect(refresh_parser.send(:path_to_uri, 'foo', hostname)).to eql("file://#{hostname}/foo")
      expect(refresh_parser.send(:path_to_uri, 'foo/bar', hostname)).to eql("file://#{hostname}/foo/bar")
      expect(refresh_parser.send(:path_to_uri, 'foo/bar-stuff', hostname)).to eql("file://#{hostname}/foo/bar-stuff")
      expect(refresh_parser.send(:path_to_uri, 'foo/C:/bar', hostname)).to eql("file://#{hostname}/foo/C:/bar")
      expect(refresh_parser.send(:path_to_uri, 'foo/[bar]', hostname)).to eql("file://#{hostname}/foo/%5Bbar%5D")
    end

    it 'handles an IPv6 hostname as expected' do
      hostname = '::1'

      expect(refresh_parser.send(:path_to_uri, 'foo', hostname)).to eql("file://[#{hostname}]/foo")
    end

    it 'handles a UNC path as expected' do
      hostname = "lab.example.com"
      file = "//foo/bar/baz"

      expect(refresh_parser.send(:path_to_uri, file, hostname)).to eql("file://#{hostname}/#{file}")
    end

    it 'handles a volume name as expected' do
      hostname = "lab.example.com"
      file = "///?/Volume{xxx-yyy-42zzz-1111-222233334444}/"
      encoded_file = URI.encode(file)

      expect(refresh_parser.send(:path_to_uri, file, hostname)).to eql("file://#{hostname}/#{encoded_file}")
    end

    it 'requires at least one argument' do
      expect { refresh_parser.send(:path_to_uri) }.to raise_error(ArgumentError)
    end
  end
end
