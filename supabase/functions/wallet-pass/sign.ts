// Detached PKCS #7 signature of the manifest, as Apple Wallet expects: signed by the Pass Type ID certificate, with
// Apple's WWDR G4 intermediate included.
import forge from "npm:node-forge@1.3.1";

export function makeSigner(certPEM: string, keyPEM: string, wwdrDER: Uint8Array, keyPassword?: string) {
  const cert = forge.pki.certificateFromPem(certPEM);
  const key = keyPassword ? forge.pki.decryptRsaPrivateKey(keyPEM, keyPassword) : forge.pki.privateKeyFromPem(keyPEM);
  const wwdr = forge.pki.certificateFromAsn1(forge.asn1.fromDer(forge.util.createBuffer(String.fromCharCode(...wwdrDER))));
  return async (manifest: Uint8Array) => {
    const p7 = forge.pkcs7.createSignedData();
    p7.content = forge.util.createBuffer(String.fromCharCode(...manifest));
    p7.addCertificate(cert);
    p7.addCertificate(wwdr);
    p7.addSigner({
      key, certificate: cert, digestAlgorithm: forge.pki.oids.sha256,
      authenticatedAttributes: [
        { type: forge.pki.oids.contentType, value: forge.pki.oids.data },
        { type: forge.pki.oids.messageDigest },
        { type: forge.pki.oids.signingTime, value: new Date() },
      ],
    });
    p7.sign({ detached: true });
    const der = forge.asn1.toDer(p7.toAsn1()).getBytes();
    const out = new Uint8Array(der.length);
    for (let i = 0; i < der.length; i++) out[i] = der.charCodeAt(i);
    return out;
  };
}
