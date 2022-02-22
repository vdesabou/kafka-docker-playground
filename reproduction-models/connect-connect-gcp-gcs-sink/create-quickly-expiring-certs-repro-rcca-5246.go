package main

import (
	"bytes"
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/asn1"
	"encoding/pem"
	"fmt"
	"io/ioutil"
	"math/big"
	"os"
	"time"
)

type PKCS8Key struct {
	Version             int
	PrivateKeyAlgorithm []asn1.ObjectIdentifier
	PrivateKey          []byte
}

func MarshalPKCS8PrivateKey(key *rsa.PrivateKey) ([]byte, error) {
	var pkey PKCS8Key
	pkey.Version = 0
	pkey.PrivateKeyAlgorithm = make([]asn1.ObjectIdentifier, 1)
	pkey.PrivateKeyAlgorithm[0] = asn1.ObjectIdentifier{1, 2, 840, 113549, 1, 1, 1}
	pkey.PrivateKey = x509.MarshalPKCS1PrivateKey(key)
	return asn1.Marshal(pkey)
}
func fatal(err error) {
	if err != nil {
		panic(err)
	}
}
func main() {
	template := x509.Certificate{
		SerialNumber: big.NewInt(time.Now().Unix()),
		Subject:      pkix.Name{Organization: []string{"localhost"}},
		NotBefore:    time.Now(),
		NotAfter:     time.Now().Add(time.Second * time.Duration(300)),
		KeyUsage:     x509.KeyUsageKeyEncipherment | x509.KeyUsageDigitalSignature,
		ExtKeyUsage:  []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		DNSNames:     []string{"localhost"},
	}
	privatekey, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		panic(err)
	}
	var certOut bytes.Buffer
	// Encode the private key into PEM data.
	bytes, err := MarshalPKCS8PrivateKey(privatekey)
	fatal(err)
	privatePem := pem.EncodeToMemory(
		&pem.Block{
			Type:  "PRIVATE KEY",
			Bytes: bytes,
		},
	)
	fmt.Printf("%s\n", privatePem)

	crt, err := x509.CreateCertificate(rand.Reader, &template, &template, &privatekey.PublicKey, privatekey)
	if err != nil {
		panic(err)
	}

	pem.Encode(&certOut, &pem.Block{Type: "CERTIFICATE", Bytes: crt})
	ioutil.WriteFile("key", privatePem, 0644)
	ioutil.WriteFile("pem", certOut.Bytes(), 0644)
	dat, err := os.ReadFile("key")
	fmt.Print(string(dat))

	dat2, err := os.ReadFile("pem")
	fmt.Print(string(dat2))
}
