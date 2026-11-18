/* Dropbear build options for the MJSXJ02HL firmware (uClibc, 41 MB of RAM, 2 MB kback partition).
 * Only ed25519 host keys and a minimal set of modern algorithms are kept. */
#define DROPBEAR_SMALL_CODE 1

/* Host keys / public keys: ed25519 only */
#define DROPBEAR_DSS 0
#define DROPBEAR_ECDSA 0
#define DROPBEAR_RSA 0
#define DROPBEAR_ED25519 1

/* Ciphers / MACs / key exchange: keep chacha20-poly1305 + aes-ctr + curve25519 */
#define DROPBEAR_ENABLE_CBC_MODE 0
#define DROPBEAR_ENABLE_GCM_MODE 0
#define DROPBEAR_SHA1_HMAC 0
#define DROPBEAR_SHA2_512_HMAC 0
#define DROPBEAR_ECDH 0
#define DROPBEAR_DH_GROUP14_SHA1 0

/* Server only: no outgoing client features */
#define DROPBEAR_CLI_PASSWORD_AUTH 0
#define DROPBEAR_CLI_PUBKEY_AUTH 0

#define DO_MOTD 0

/* The session shell must find the firmware tools, notably "scp" for scp -O */
#define DEFAULT_PATH "/backk/bin:/usr/sbin:/usr/bin:/sbin:/bin:/mnt/mmc"
#define DEFAULT_ROOT_PATH "/backk/bin:/usr/sbin:/usr/bin:/sbin:/bin:/mnt/mmc"

/* Few simultaneous connections: the camera has very little free RAM */
#define MAX_UNAUTH_CLIENTS 3
#define MAX_AUTH_TRIES 3
