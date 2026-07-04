import Testing
import Foundation
@testable import Orchard

// Pure validators extracted from the Add DNS / Add Network forms.

@Test("Domain validation: well-formed domains pass")
func domainValid() {
    for d in ["example.com", "a.b.c", "test", "my-app.local", "sub.domain.example.com"] {
        #expect(InputValidation.isValidDomainName(d), "\(d) should be valid")
    }
}

@Test("Domain validation: malformed domains are rejected")
func domainInvalid() {
    for d in ["", "-foo.com", "foo-.com", "foo..bar", "café.com", "foo/bar"] {
        #expect(!InputValidation.isValidDomainName(d), "\(d) should be rejected")
    }
}

@Test("Network-name validation: single alphanumeric labels pass, others fail")
func networkName() {
    for ok in ["bridge", "my-net", "net1", "a"] {
        #expect(InputValidation.isValidNetworkName(ok), "\(ok) should be valid")
    }
    for bad in ["", "-net", "net-", "my_net", "a b", "with.dot"] {
        #expect(!InputValidation.isValidNetworkName(bad), "\(bad) should be rejected")
    }
}

@Test("Subnet validation: dotted-quad + /prefix passes, missing/oversized prefix fails")
func subnet() {
    for ok in ["10.0.0.0/24", "192.168.1.0/16", "0.0.0.0/0", "172.16.0.0/32"] {
        #expect(InputValidation.isValidSubnet(ok), "\(ok) should be valid")
    }
    for bad in ["10.0.0.0", "10.0.0.0/33", "foo/24", "10.0.0/24", "",
                "999.999.999.999/24", "256.0.0.0/24"] {
        #expect(!InputValidation.isValidSubnet(bad), "\(bad) should be rejected")
    }
}
