# Installer Lingkungan Praktik Agentic Security

Folder ini berisi installer yang sama untuk VPS-Attacker instruktur dan perangkat peserta. Installer menyiapkan toolchain Sesi 1 dan Sesi 2, tetapi tidak memasang atau menjalankan aplikasi target pada VPS-Victim.

Profil `instructor` sudah dikalibrasi end-to-end pada VPS-Attacker Ubuntu 24.04 x86_64 tanggal 24 November 2026. Instalasi nyata, rerun idempotent, digest image, gateway HTTPS, Basic Auth, login native Xalgorix, dan verifikasi pasif telah diuji tanpa menjalankan active scan. Jalur Kali memakai compatibility floor karena Kali adalah rolling release.

## Mulai cepat peserta

Gunakan Ubuntu 24.04 x86_64 atau Kali Linux x86_64 pada perangkat atau VM khusus latihan. Siapkan sedikitnya 8 GB RAM dan 50 GB disk kosong, lalu jalankan:

```bash
git clone https://github.com/petanianu1337/prektek-lab.git
cd prektek-lab

./install.sh \
  --dry-run \
  --profile participant \
  --workspace "$HOME/training-workspace"

./install.sh \
  --profile participant \
  --workspace "$HOME/training-workspace"
```

Installer tidak meminta API key dan tidak menjalankan scan. Perintah `opencode` langsung tersedia melalui launcher `/usr/local/bin/opencode`; installer tidak mengubah file profile shell peserta. Logout/login tetap diperlukan agar membership grup Docker aktif penuh. Xalgorix peserta tetap lokal pada `http://127.0.0.1:9137`; credential unik perangkat tersimpan dengan permission `0600` di `~/.config/praktek-lab/xalgorix.env`.

Jangan memasukkan target ke agent atau scanner sebelum instruktur menyampaikan scope dan `~/training-workspace/scope.env` sudah diisi serta disetujui.

## Tujuan dan batasan

Toolchain yang disiapkan:

- utilitas host untuk source review dan evidence;
- Docker Engine dan Docker Compose;
- OpenCode;
- RedteamAgent pada project scope;
- VulnVerify Skills pada project scope yang sama;
- Trail of Bits Skills terpilih pada project scope OpenCode;
- Xalgorix dalam container terisolasi;
- Playwright MCP melalui image Docker, kecuali dilewati secara eksplisit.

Installer tidak:

- mengubah SSH atau firewall;
- menyimpan API key/provider key;
- memasukkan target ke scanner;
- menjalankan active scan;
- memasang target lab pada VPS-Victim;
- menghapus source, evidence, atau laporan saat uninstall biasa.

Docker pada Ubuntu menggunakan grup `docker`. Installer menambahkan user pelatihan ke grup tersebut agar RedteamAgent dan Playwright MCP dapat berjalan dari OpenCode. Grup `docker` setara akses root, sehingga toolchain hanya boleh dipasang pada VPS, VM, WSL, atau perangkat yang memang dikhususkan untuk latihan. Membership baru aktif penuh setelah logout/login; selama instalasi pertama digunakan shim lokal `sudo docker` yang tidak disimpan dalam konfigurasi MCP.

## Struktur

```text
praktek-lab/
├── install.sh
├── uninstall.sh
├── versions.env
├── lib/
│   ├── common.sh
│   ├── docker-shim/
│   │   └── docker
│   └── opencode-launcher
├── installers/
│   ├── 01-system.sh
│   ├── 02-docker.sh
│   ├── 03-opencode.sh
│   ├── 04-redteam-agent.sh
│   ├── 05-vulnverify.sh
│   ├── 06-trailofbits.sh
│   ├── 06-xalgorix.sh
│   └── 07-playwright.sh
├── checks/
│   ├── preflight.sh
│   └── verify.sh
├── config/
│   ├── scope.env.example
│   ├── xalgorix.caddy.template
│   └── xalgorix.compose.yml
└── README.md
```

`install.sh` adalah satu-satunya entry point instalasi. Modul dipanggil berurutan setelah preflight, kemudian `verify.sh` dijalankan tanpa active scan. Dua modul bernomor `06` dijalankan deterministik menurut nama file: Trail of Bits terlebih dahulu, lalu Xalgorix.

## Platform acuan

| Resource | Minimum | Rekomendasi |
| --- | ---: | ---: |
| OS | Ubuntu 24.04 LTS atau Kali Linux rolling | Ubuntu 24.04 LTS bersih |
| Arsitektur | x86_64 | x86_64 |
| CPU | 2 vCPU, concurrency 1 | 4 vCPU atau lebih |
| RAM | 7.500 MiB terbaca (kelas 8 GB) | 15.000 MiB atau lebih |
| Disk kosong | 50 GB | 80 GB |

Windows menggunakan WSL2 atau VM Ubuntu. Kali VM didukung melalui paket resmi `docker.io` dan pemeriksaan versi minimum Docker/Compose; Ubuntu 24.04 memakai exact apt pins. Arsitektur ARM belum dibuka karena seluruh digest kelas baru dikalibrasi pada amd64.

## Profil instalasi

| Perilaku | `participant` | `instructor` |
| --- | --- | --- |
| Base toolchain | Ya | Ya |
| Xalgorix bind `127.0.0.1:9137` | Ya | Ya |
| Xalgorix native login | Ya | Ya |
| Gateway HTTPS publik | Tidak pernah | Dengan domain atau `--xalgorix-public-ip` |
| Gateway Basic Auth | Tidak | Ya, jika domain atau IP publik diberikan |
| Mengubah SSH/firewall | Tidak | Tidak |

Setiap peserta memasang Xalgorix Docker lokal dan menerima credential unik yang dibuat pada perangkatnya sendiri. Dashboard peserta hanya bind ke `127.0.0.1:9137`; mereka tidak menerima credential Xalgorix VPS instruktur. Profil `instructor` dapat memakai domain, IP publik + port, atau tetap loopback.

Perlindungan dashboard tidak menghambat scanning. Browser masuk melalui HTTPS, Basic Auth, lalu login native Xalgorix. Engine Xalgorix menggunakan koneksi keluar yang terpisah menuju target yang sudah disetujui.

## Versi dan status pin

Semua pin terpusat di `versions.env`; file itu tidak boleh berisi secret. `PINS_FINALIZED=1` mencakup OpenCode, commit RedteamAgent, VulnVerify, Trail of Bits Skills, Katana, base Kali, Xalgorix, dan Playwright MCP.

RedteamAgent upstream masih menyebut alias `latest`, tetapi wrapper tidak mempercayai alias registry: Katana ditarik dengan digest tetap, base Kali diganti melalui Dockerfile overlay digest-pinned, dan image hasil build diberi label provenance. Checkout upstream tetap bersih pada commit yang dikunci. Paket dari repository Kali di dalam image tetap mengikuti snapshot repository saat build; karena itu hasil image lokal tidak bit-for-bit reproducible tanpa registry image kelas sendiri.

## Dry-run

Jalankan dari folder `praktek-lab`:

```bash
./install.sh \
  --dry-run \
  --profile participant \
  --workspace /home/PESERTA/training-workspace
```

Contoh rencana profil instruktur:

```bash
./install.sh \
  --dry-run \
  --profile instructor \
  --workspace /home/INSTRUKTUR/training-workspace \
  --xalgorix-public-ip 203.0.113.10 \
  --xalgorix-public-port 9443
```

Dry-run tidak mengunduh file, memasang paket, membuat credential, menjalankan container, atau mengubah konfigurasi sistem.

## Instalasi

Peserta:

```bash
./install.sh \
  --profile participant \
  --workspace /home/PESERTA/training-workspace
```

Instruktur dengan dashboard HTTPS:

```bash
./install.sh \
  --profile instructor \
  --workspace /home/INSTRUKTUR/training-workspace \
  --xalgorix-public-ip 203.0.113.10 \
  --xalgorix-public-port 9443
```

Mode IP memakai sertifikat self-signed dengan SAN IP pada port yang dipilih. Browser akan menampilkan peringatan sampai sertifikat dipercaya. Xalgorix tetap bind ke loopback; hanya gateway Caddy yang listen publik dan request harus melewati Basic Auth sebelum form login native.

Mode privileged Xalgorix tidak aktif secara default. Jika fungsi jaringan tingkat rendah benar-benar diperlukan pada VPS latihan khusus, instruktur dapat melakukan uji terpisah dengan `--xalgorix-privileged`. Mode ini memberi container kewenangan host yang sangat tinggi dan tidak boleh menjadi default peserta.

Playwright dapat dilewati jika tidak dipakai dalam rundown:

```bash
./install.sh --profile participant --skip-playwright
```

## Idempotensi

Installer aman dijalankan ulang dengan parameter yang sama:

- repository Git diverifikasi origin dan commit-nya;
- runtime RedteamAgent dan VulnVerify memakai marker commit;
- MCP Metasploit bawaan RedteamAgent dinonaktifkan sekali saat instalasi karena `msfrpcd` tidak digunakan dalam materi;
- RedteamAgent dipasang melalui staging directory dan hasil gagal dipertahankan sebagai backup;
- credential Xalgorix yang sudah ada dipertahankan;
- volume Xalgorix dipertahankan;
- container dikelola melalui Docker Compose;
- konfigurasi MCP Playwright tidak ditambahkan ulang jika sudah terdaftar.

## Trail of Bits Skills untuk OpenCode

Repository [Trail of Bits Skills](https://github.com/trailofbits/skills) adalah marketplace besar untuk Claude Code dan Codex, bukan paket OpenCode tunggal. Installer tidak mengaktifkan seluruh marketplace. Hanya dua skill yang sudah direview dan relevan dengan latihan yang disalin ke `.opencode/skills/`:

- `sharp-edges` untuk mengidentifikasi API, konfigurasi, dan default yang mudah disalahgunakan;
- `cvss-scoring` untuk menyusun vector CVSS v4.0 dengan justifikasi.

Pembatasannya:

- commit repository dikunci di `versions.env`;
- plugin, hook, workflow, subagent, dan skill lain tidak dipasang;
- `.calcifier` pada `cvss-scoring` sengaja dikecualikan;
- skill yang namanya bertabrakan dengan VulnVerify tidak disalin;
- source checkout disimpan untuk audit, tetapi OpenCode hanya menemukan dua skill allowlist pada project RedteamAgent.

`audit-context-building` tidak dipasang karena versi marketplace bergantung pada workflow dan subagent yang tidak tersedia sebagai skill native OpenCode. Source mapping tetap ditangani RedteamAgent.

Installer berhenti jika menemukan runtime yang tidak dikenali atau versi berbeda. Ia tidak menimpa perubahan semacam itu secara otomatis.

MCP Metasploit bawaan RedteamAgent dinonaktifkan secara default karena sesi ini berfokus pada source review dan web verification, bukan eksploitasi Metasploit. Installer menulis marker kebijakan satu kali; perubahan manual yang dilakukan instruktur setelah marker tersedia tidak ditimpa saat rerun.

## Credential dan API key

Credential dibuat hanya saat instalasi nyata dan disimpan dengan mode `0600`:

```text
~/.config/praktek-lab/xalgorix.env
~/.config/praktek-lab/xalgorix-gateway.env
```

Nilainya tidak dicetak oleh installer. File pertama berisi login native Xalgorix dan parameter Compose; pada profil peserta file ini hanya berada di perangkat peserta tersebut. File kedua hanya dibuat untuk profil instruktur yang mengaktifkan gateway domain/IP dan berisi login gateway yang berbeda. Credential VPS instruktur tidak pernah disalin ke paket peserta.

API key model tidak dibuat atau ditulis oleh installer. Instruktur dan peserta memasukkannya melalui setup/UI resmi tool setelah kebijakan distribusi secret ditentukan. Jangan menaruh key di `versions.env`, source, transcript, laporan, atau submission.

## Xalgorix

Compose menerapkan guardrail berikut:

- host port hanya `127.0.0.1:9137`;
- login native selalu dikonfigurasi;
- tidak ada mount Docker socket;
- auto-update dalam container dinonaktifkan;
- akses ke target private/loopback tidak diaktifkan otomatis;
- data berada dalam volume `training-xalgorix-data`;
- privileged default `false`;
- jumlah assessment bersamaan dibatasi satu instance.

Image resmi Xalgorix berukuran sekitar 6–8 GB karena sudah memuat tool keamanan dan Chromium. Unduh/unpack pertama dapat lama; rerun memakai image yang sudah tersimpan.

Untuk peserta, dashboard dibuka melalui browser lokal pada `http://127.0.0.1:9137` menggunakan credential lokalnya sendiri. Peserta tidak mengakses instance atau credential Xalgorix VPS instruktur.

Untuk profil instruktur, Caddy dapat meneruskan HTTPS dari domain atau IP publik + port ke backend loopback dan menambahkan Basic Auth. Header gateway dibuang sebelum diteruskan agar tidak dianggap token API oleh Xalgorix; form login native tetap menjadi lapis kedua. Installer tidak mengubah firewall atau security group cloud.

## Scope wajib sebelum pengujian

Installer membuat:

```text
~/training-workspace/scope.env
```

Nilai awal `SCOPE_ACCEPTED=NO`. Target tidak boleh dimasukkan ke OpenCode, RedteamAgent, Xalgorix, Playwright, curl, atau tool lain sebelum:

1. instruktur mengisi owner, waktu izin, target, rate limit, concurrency, dan tindakan terlarang;
2. peserta membaca batasannya;
3. peserta mengubah nilai menjadi `SCOPE_ACCEPTED=YES` sebagai bukti persetujuan.

Target kandidat kelas adalah `lab-hw.my.id` pada port 443 dan 8443–8447 serta instance lokal peserta. Domain/IP lain tetap out of scope walaupun ditemukan crawler.

Scope file adalah guardrail prosedural, bukan sandbox jaringan. OpenCode, Playwright MCP, Xalgorix, Docker, dan agent AI tetap harus diawasi manusia.

## Verifikasi pasif

Verifikasi dapat diulang dengan:

```bash
./checks/verify.sh \
  --profile participant \
  --workspace /home/PESERTA/training-workspace
```

Pemeriksaan meliputi:

- versi OpenCode;
- commit RedteamAgent dan VulnVerify;
- Docker dan Compose;
- status container Xalgorix;
- binding dashboard hanya ke loopback;
- keberadaan konfigurasi native login tanpa mencetak nilainya;
- image dan registrasi MCP Playwright jika dipakai;
- penolakan request tanpa Basic Auth pada gateway instruktur;
- status persetujuan scope;
- pembuatan `environment.txt` tanpa secret.

`verify.sh` tidak mengakses `lab-hw.my.id`, membuka browser ke target, atau menjalankan scanner. Smoke test konektivitas dan scan dilakukan kemudian sebagai langkah terpisah setelah scope disetujui.

## Workspace hasil instalasi

```text
training-workspace/
├── scope.env
├── environment.txt
├── tooling/
│   ├── sources/
│   ├── redteam-agent/
│   ├── vulnverify-skills/
│   ├── trailofbits-skills/
│   └── xalgorix/
├── sesi1/
│   ├── targets/
│   ├── engagements/
│   ├── evidence/
│   └── reports/
└── sesi2/
    ├── procureflow/
    ├── evidence/
    ├── transcript/
    └── submission/
```

OpenCode dijalankan dari `tooling/redteam-agent` agar agent RedteamAgent, VulnVerify Skills, dan konfigurasi MCP project-scoped ditemukan bersama. Source target dan `ProcureFlow.zip` tidak disalin otomatis oleh installer.

## Uninstall terbatas

Lihat rencana dahulu:

```bash
./uninstall.sh \
  --dry-run \
  --profile participant \
  --workspace /home/PESERTA/training-workspace
```

Eksekusi nyata membutuhkan `--yes`. Secara default uninstaller hanya menghentikan dan menghapus container Xalgorix serta melepas snippet Caddy untuk profil instruktur. Volume, credential, source, evidence, OpenCode, Docker, dan paket sistem dipertahankan.

`--purge-data` juga menghapus volume dan credential Xalgorix. Tindakan tersebut tidak dapat dipulihkan oleh installer, tetapi tetap tidak menghapus workspace atau evidence peserta.

## Referensi utama

- [OpenCode documentation](https://opencode.ai/docs/)
- [RedteamAgent](https://github.com/NeoTheCapt/RedteamAgent)
- [VulnVerify Skills](https://github.com/roomkangali/vulnverify-skills)
- [Xalgorix](https://github.com/xalgorix/xalgorix)
- [Playwright MCP](https://github.com/microsoft/playwright-mcp)
