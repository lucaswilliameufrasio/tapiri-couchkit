package com.lucas.common;

import android.content.SharedPreferences;
import android.util.Base64;

import java.io.ByteArrayOutputStream;
import java.io.DataInputStream;
import java.io.OutputStream;
import java.math.BigInteger;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.security.KeyFactory;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.Signature;
import java.security.interfaces.RSAPublicKey;
import java.security.spec.PKCS8EncodedKeySpec;
import java.security.spec.X509EncodedKeySpec;

/**
 * Cliente ADB minimo: fala com o adbd do proprio aparelho (127.0.0.1:5555) para
 * rodar comandos de shell com a permissao do ADB, sem PC. Exige "Depuracao ADB"
 * ligada e uma unica autorizacao na TV ("Sempre permitir").
 */
public final class Adb {
    private static final int A_CNXN = 0x4e584e43, A_AUTH = 0x48545541, A_OPEN = 0x4e45504f;
    private static final int A_OKAY = 0x59414b4f, A_WRTE = 0x45545257, A_CLSE = 0x45534c43;
    private static final int AUTH_TOKEN = 1, AUTH_SIGNATURE = 2, AUTH_RSAPUBLICKEY = 3;
    private static final int MAX_DATA = 256 * 1024;
    /** DigestInfo do SHA-1: o adbd assina o token como se fosse o hash. */
    private static final byte[] SHA1_PREFIX = {0x30, 0x21, 0x30, 0x09, 0x06, 0x05, 0x2b, 0x0e, 0x03, 0x02, 0x1a, 0x05, 0x00, 0x04, 0x14};

    private static SharedPreferences prefs;
    private static KeyPair keys;
    /** idle, waiting (aguardando OK na TV), ok ou error:mensagem. */
    public static volatile String state = "idle";

    private Adb() {}

    public static void init(SharedPreferences p) { prefs = p; }

    /** Roda um comando de shell e devolve a saida. Bloqueia ate o fim ou o timeout. */
    public static String shell(String cmd, int timeoutMs) throws Exception {
        Socket s = new Socket();
        try {
            s.connect(new InetSocketAddress("127.0.0.1", 5555), 3000);
            s.setSoTimeout(timeoutMs);
            OutputStream out = s.getOutputStream();
            DataInputStream in = new DataInputStream(s.getInputStream());
            handshake(s, out, in);
            state = "ok";
            send(out, A_OPEN, 1, 0, (("shell:" + cmd) + "\0").getBytes("UTF-8"));
            ByteArrayOutputStream result = new ByteArrayOutputStream();
            while (true) {
                int[] h = new int[3];
                byte[] data = read(in, h);
                if (h[0] == A_WRTE) { result.write(data); send(out, A_OKAY, 1, h[1], new byte[0]); }
                else if (h[0] == A_CLSE) break;
                else if (h[0] != A_OKAY) throw new IllegalStateException("resposta inesperada do adbd");
            }
            return result.toString("UTF-8");
        } catch (Exception e) {
            if (!"ok".equals(state)) state = "error:" + e.getMessage();
            throw e;
        } finally {
            try { s.close(); } catch (Exception ignore) {}
        }
    }

    private static void handshake(Socket s, OutputStream out, DataInputStream in) throws Exception {
        send(out, A_CNXN, 0x01000000, MAX_DATA, "host::couchkit\0".getBytes("UTF-8"));
        int[] h = new int[3];
        byte[] data = read(in, h);
        boolean signed = false, keySent = false;
        while (h[0] == A_AUTH) {
            if (h[1] != AUTH_TOKEN) throw new IllegalStateException("autenticacao inesperada");
            if (keySent) throw new IllegalStateException("autorizacao negada na TV");
            if (!signed) { send(out, A_AUTH, AUTH_SIGNATURE, 0, sign(data)); signed = true; }
            else {
                state = "waiting";
                s.setSoTimeout(90000);
                send(out, A_AUTH, AUTH_RSAPUBLICKEY, 0, publicKeyLine());
                keySent = true;
            }
            data = read(in, h);
        }
        if (h[0] != A_CNXN) throw new IllegalStateException("adbd nao respondeu (Depuracao ADB ligada?)");
    }

    private static synchronized KeyPair keys() throws Exception {
        if (keys != null) return keys;
        KeyFactory kf = KeyFactory.getInstance("RSA");
        String priv = prefs.getString("adb_priv", null), pub = prefs.getString("adb_pub", null);
        if (priv != null && pub != null) {
            keys = new KeyPair(kf.generatePublic(new X509EncodedKeySpec(Base64.decode(pub, Base64.NO_WRAP))),
                    kf.generatePrivate(new PKCS8EncodedKeySpec(Base64.decode(priv, Base64.NO_WRAP))));
            return keys;
        }
        KeyPairGenerator g = KeyPairGenerator.getInstance("RSA");
        g.initialize(2048);
        keys = g.generateKeyPair();
        prefs.edit()
                .putString("adb_priv", Base64.encodeToString(keys.getPrivate().getEncoded(), Base64.NO_WRAP))
                .putString("adb_pub", Base64.encodeToString(keys.getPublic().getEncoded(), Base64.NO_WRAP)).apply();
        return keys;
    }

    private static byte[] sign(byte[] token) throws Exception {
        Signature sig = Signature.getInstance("NONEwithRSA");
        sig.initSign(keys().getPrivate());
        sig.update(SHA1_PREFIX);
        sig.update(token);
        return sig.sign();
    }

    private static byte[] publicKeyLine() throws Exception {
        byte[] blob = publicKeyBlob((RSAPublicKey) keys().getPublic());
        return (Base64.encodeToString(blob, Base64.NO_WRAP) + " couchkit@stickhub\0").getBytes("UTF-8");
    }

    /** Formato RSAPublicKey do Android (mincrypt): tamanho, n0inv, n, R^2 mod n, expoente. */
    public static byte[] publicKeyBlob(RSAPublicKey k) {
        BigInteger n = k.getModulus(), r32 = BigInteger.ONE.shiftLeft(32);
        int n0inv = r32.subtract(n.mod(r32).modInverse(r32)).intValue();
        BigInteger rr = BigInteger.ONE.shiftLeft(4096).mod(n);
        ByteBuffer b = ByteBuffer.allocate(4 + 4 + 256 + 256 + 4).order(ByteOrder.LITTLE_ENDIAN);
        b.putInt(64).putInt(n0inv).put(le(n, 256)).put(le(rr, 256)).putInt(k.getPublicExponent().intValue());
        return b.array();
    }

    private static byte[] le(BigInteger v, int len) {
        byte[] be = v.toByteArray(), out = new byte[len];
        for (int i = 0; i < len && i < be.length; i++) out[i] = be[be.length - 1 - i];
        return out;
    }

    private static void send(OutputStream o, int cmd, int a0, int a1, byte[] data) throws Exception {
        int sum = 0;
        for (byte x : data) sum += x & 0xff;
        ByteBuffer h = ByteBuffer.allocate(24).order(ByteOrder.LITTLE_ENDIAN);
        h.putInt(cmd).putInt(a0).putInt(a1).putInt(data.length).putInt(sum).putInt(cmd ^ 0xffffffff);
        o.write(h.array());
        o.write(data);
        o.flush();
    }

    /** Le uma mensagem; head recebe {comando, arg0, arg1}. */
    private static byte[] read(DataInputStream in, int[] head) throws Exception {
        byte[] hb = new byte[24];
        in.readFully(hb);
        ByteBuffer h = ByteBuffer.wrap(hb).order(ByteOrder.LITTLE_ENDIAN);
        head[0] = h.getInt(); head[1] = h.getInt(); head[2] = h.getInt();
        int len = h.getInt();
        if (len < 0 || len > MAX_DATA) throw new IllegalStateException("mensagem invalida do adbd");
        byte[] data = new byte[len];
        in.readFully(data);
        return data;
    }
}
