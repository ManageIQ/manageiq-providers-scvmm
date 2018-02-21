require 'manageiq/network_discovery/port'

module ManageIQ
  module Providers
    module Microsoft
      class Discovery
        MSWIN_PORTS = [
          135, # Microsoft Remote Procedure Call (RPC)
          139  # NetBIOS Session (TCP), Windows File and Printer Sharing
        ].freeze

        SCVMM_PORTS = MSWIN_PORTS + [
          8100 # VMM HTTP Console (WCF)
        ].freeze

        VIRTUAL_SERVER_PORT = 5900 # Microsoft Virtual Machine Remote Control Client

        def self.probe(ost)
          ost.hypervisor << :msvirtualserver if ManageIQ::NetworkDiscovery::Port.open?(ost, VIRTUAL_SERVER_PORT)
          ost.hypervisor << :scvmm if ManageIQ::NetworkDiscovery::Port.all_open?(ost, SCVMM_PORTS)
          ost.os << :mswin  if ManageIQ::NetworkDiscovery::Port.all_open?(ost, MSWIN_PORTS)
        end
      end
    end
  end
end
