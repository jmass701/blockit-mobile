package com.blockit.mobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.nio.ByteBuffer

/**
 * BlockVpnService — website blocking via a local, on-device DNS filter. This is
 * the Android equivalent of blocker_common.apply_hosts_block(): where the
 * Windows app redirects blocked domains to 127.0.0.1 in the hosts file, here we
 * run a tiny VpnService that intercepts DNS queries and answers NXDOMAIN for any
 * currently-LOCKED domain (and its subdomains / www. variant), while forwarding
 * every other query to an upstream resolver — normally 8.8.8.8, or the
 * CleanBrowsing Family Filter resolver when the "strict" adult-content filter
 * is turned on in Settings, which blocks porn/adult sites at the DNS level
 * without needing a manual domain list. No traffic is proxied through any
 * remote server — this is purely on-device DNS interception, the same pattern
 * used by DNS66 / Blokada.
 *
 * The locked-domain set is read straight from blocklist.json / state.json via
 * JsonState each cycle, so unlocking a site (which mutates state.json) stops it
 * being filtered within one tick — no engine round-trip required.
 *
 * NOTE (scope): this intentionally handles only DNS (UDP/53) over the tun, which
 * is sufficient to block name resolution. It is not a full packet-forwarding
 * VPN. IPv6 DNS and DNS-over-HTTPS bypass are known limitations (see report).
 */
class BlockVpnService : VpnService() {

    @Volatile private var running = false
    private var tun: ParcelFileDescriptor? = null
    private var worker: Thread? = null

    // Virtual addresses inside the tun subnet. The OS is told the DNS server is
    // DNS_SENTINEL, and only that /32 is routed into the tun — so only DNS
    // packets reach us; all other traffic uses the normal network untouched.
    private val tunAddress = "10.111.222.1"
    private val dnsSentinel = "10.111.222.2"

    // Normal upstream resolver vs. a content-filtering resolver (CleanBrowsing
    // Family Filter — blocks porn/adult sites and enforces safe search at the
    // DNS level, no manual domain list needed). Which one we forward allowed
    // queries to is controlled by config.json's "strict" adult-content-filter
    // toggle, re-read on the same cadence as lockedDomains.
    private val normalUpstreamDns = "8.8.8.8"
    private val filteredUpstreamDns = "185.228.168.168"
    @Volatile private var upstreamDns = normalUpstreamDns

    @Volatile private var lockedDomains: Set<String> = emptySet()

    private fun refreshUpstreamDns() {
        upstreamDns = if (JsonState.adultContentFilterEnabled(this)) {
            filteredUpstreamDns
        } else {
            normalUpstreamDns
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopVpn()
                return START_NOT_STICKY
            }
            ACTION_REFRESH -> {
                lockedDomains = JsonState.lockedDomains(this)
                refreshUpstreamDns()
                return START_STICKY
            }
        }
        if (!running) startVpn()
        return START_STICKY
    }

    private fun startVpn() {
        startAsForeground()
        lockedDomains = JsonState.lockedDomains(this)
        refreshUpstreamDns()

        val builder = Builder()
            .setSession("BlockIT DNS filter")
            .addAddress(tunAddress, 24)
            .addDnsServer(dnsSentinel)
            // Route ONLY the sentinel DNS address into the tun, so we see DNS
            // packets and nothing else.
            .addRoute(dnsSentinel, 32)
        // Don't capture our own app's traffic (avoid loops on the upstream
        // forward socket, which is also protected below).
        try {
            builder.addDisallowedApplication(packageName)
        } catch (e: Exception) {
            // Package not found (shouldn't happen) — ignore.
        }

        val descriptor = builder.establish() ?: run {
            DebugLog.log(this, "VPN", "builder.establish() returned null — VPN failed to start")
            stopVpn()
            return
        }
        tun = descriptor
        running = true
        DebugLog.log(this, "VPN", "started, lockedDomains=$lockedDomains")
        EngineEvents.emit("vpn_started")

        worker = Thread { runLoop(descriptor) }.also { it.start() }
    }

    private fun runLoop(descriptor: ParcelFileDescriptor) {
        val input = FileInputStream(descriptor.fileDescriptor)
        val output = FileOutputStream(descriptor.fileDescriptor)
        val buffer = ByteArray(32767)

        // One protected socket for forwarding allowed queries upstream. protect()
        // keeps its packets OUT of the tun so they actually hit the network.
        val forwardSocket = DatagramSocket()
        protect(forwardSocket)
        forwardSocket.soTimeout = 5000

        var lastDomainRefresh = 0L
        try {
            while (running) {
                // Re-read the locked set every ~3s so a time-based unlock
                // expiring (is_item_unlocked going false again) re-blocks the
                // site without needing an explicit refresh intent.
                val now = System.currentTimeMillis()
                if (now - lastDomainRefresh > 3000) {
                    lockedDomains = JsonState.lockedDomains(this)
                    refreshUpstreamDns()
                    lastDomainRefresh = now
                }

                val length = try {
                    input.read(buffer)
                } catch (e: Exception) {
                    if (!running) break else continue
                }
                if (length <= 0) continue

                val packet = buffer.copyOf(length)
                val response = handlePacket(packet, forwardSocket) ?: continue
                try {
                    output.write(response)
                } catch (e: Exception) {
                    // tun closed under us — loop exit will handle it.
                }
            }
        } finally {
            try { forwardSocket.close() } catch (e: Exception) {}
            try { input.close() } catch (e: Exception) {}
            try { output.close() } catch (e: Exception) {}
        }
    }

    /**
     * Parses one IPv4/UDP/53 packet. Returns the raw IP packet to write back
     * into the tun (a crafted NXDOMAIN for blocked names, or the forwarded
     * upstream answer for allowed ones), or null if it isn't a DNS query we
     * handle.
     */
    private fun handlePacket(packet: ByteArray, forwardSocket: DatagramSocket): ByteArray? {
        if (packet.size < 28) return null
        val version = (packet[0].toInt() ushr 4) and 0x0F
        if (version != 4) return null // IPv6 not handled (documented limitation)
        val ihl = (packet[0].toInt() and 0x0F) * 4
        val protocol = packet[9].toInt() and 0xFF
        if (protocol != 17) return null // UDP only

        val udpStart = ihl
        if (packet.size < udpStart + 8) return null
        val dstPort = ((packet[udpStart + 2].toInt() and 0xFF) shl 8) or
            (packet[udpStart + 3].toInt() and 0xFF)
        if (dstPort != 53) return null

        val payloadStart = udpStart + 8
        if (packet.size <= payloadStart) return null
        val dnsQuery = packet.copyOfRange(payloadStart, packet.size)

        val domain = parseDnsQuestion(dnsQuery) ?: return null

        val srcAddr = packet.copyOfRange(12, 16)
        val dstAddr = packet.copyOfRange(16, 20)
        val srcPort = ((packet[udpStart].toInt() and 0xFF) shl 8) or
            (packet[udpStart + 1].toInt() and 0xFF)

        val answer: ByteArray = if (isBlocked(domain)) {
            DebugLog.log(this, "VPN", "DNS BLOCKED domain=$domain")
            EngineEvents.emit("dns_blocked")
            buildNxDomain(dnsQuery)
        } else {
            DebugLog.log(this, "VPN", "DNS allowed domain=$domain")
            forwardUpstream(dnsQuery, forwardSocket) ?: return null
        }

        // Response IP packet: swap src/dst addr and ports, src port becomes 53.
        return buildUdpIpPacket(
            srcAddr = dstAddr, // was the destination (sentinel)
            dstAddr = srcAddr, // back to the querying app
            srcPort = 53,
            dstPort = srcPort,
            payload = answer
        )
    }

    /**
     * True if [domain] is locked: an exact match, or a subdomain of a locked
     * domain (which also covers the www. variant the hosts file handled).
     */
    private fun isBlocked(domain: String): Boolean {
        val name = domain.trim().lowercase().trimEnd('.')
        for (d in lockedDomains) {
            if (name == d || name.endsWith(".$d")) return true
        }
        return false
    }

    /** Extracts the QNAME from the first DNS question. */
    private fun parseDnsQuestion(dns: ByteArray): String? {
        if (dns.size < 13) return null
        var pos = 12 // header is 12 bytes; questions follow
        val sb = StringBuilder()
        while (pos < dns.size) {
            val len = dns[pos].toInt() and 0xFF
            if (len == 0) break
            // Compression pointers shouldn't appear in a question QNAME.
            if (len and 0xC0 != 0) return null
            pos++
            if (pos + len > dns.size) return null
            if (sb.isNotEmpty()) sb.append('.')
            sb.append(String(dns, pos, len, Charsets.US_ASCII))
            pos += len
        }
        return if (sb.isEmpty()) null else sb.toString()
    }

    /** Turns a DNS query into an NXDOMAIN response (RCODE=3), question echoed. */
    private fun buildNxDomain(query: ByteArray): ByteArray {
        val resp = query.copyOf()
        // Flags byte 2: set QR (response).
        resp[2] = (resp[2].toInt() or 0x80).toByte()
        // Flags byte 3: set RA (recursion available) and RCODE=3 (name error).
        resp[3] = ((resp[3].toInt() and 0xF0) or 0x03 or 0x80).toByte()
        // ancount/nscount/arcount stay 0 (bytes 6..11 of a bare query).
        return resp
    }

    /** Forwards a DNS query to the real upstream resolver and returns its reply. */
    private fun forwardUpstream(query: ByteArray, socket: DatagramSocket): ByteArray? {
        return try {
            val server = InetAddress.getByName(upstreamDns)
            socket.send(DatagramPacket(query, query.size, server, 53))
            val buf = ByteArray(4096)
            val reply = DatagramPacket(buf, buf.size)
            socket.receive(reply)
            buf.copyOf(reply.length)
        } catch (e: Exception) {
            null
        }
    }

    /** Builds an IPv4 + UDP packet with a correct IP checksum (UDP checksum 0). */
    private fun buildUdpIpPacket(
        srcAddr: ByteArray,
        dstAddr: ByteArray,
        srcPort: Int,
        dstPort: Int,
        payload: ByteArray
    ): ByteArray {
        val udpLen = 8 + payload.size
        val totalLen = 20 + udpLen
        val buf = ByteBuffer.allocate(totalLen)

        // ---- IPv4 header (20 bytes, no options) ----
        buf.put(0x45.toByte()) // version 4, IHL 5
        buf.put(0)             // DSCP/ECN
        buf.putShort(totalLen.toShort())
        buf.putShort(0)        // identification
        buf.putShort(0x4000.toShort()) // flags: Don't Fragment
        buf.put(64)            // TTL
        buf.put(17)            // protocol UDP
        buf.putShort(0)        // header checksum placeholder
        buf.put(srcAddr)
        buf.put(dstAddr)

        // ---- UDP header (8 bytes) ----
        buf.putShort(srcPort.toShort())
        buf.putShort(dstPort.toShort())
        buf.putShort(udpLen.toShort())
        buf.putShort(0)        // UDP checksum optional for IPv4 -> 0

        buf.put(payload)

        val packet = buf.array()
        // Compute and patch the IPv4 header checksum (bytes 10..11).
        val checksum = ipChecksum(packet, 0, 20)
        packet[10] = ((checksum ushr 8) and 0xFF).toByte()
        packet[11] = (checksum and 0xFF).toByte()
        return packet
    }

    private fun ipChecksum(data: ByteArray, offset: Int, length: Int): Int {
        var sum = 0
        var i = offset
        val end = offset + length
        while (i < end - 1) {
            sum += ((data[i].toInt() and 0xFF) shl 8) or (data[i + 1].toInt() and 0xFF)
            i += 2
        }
        if (i < end) sum += (data[i].toInt() and 0xFF) shl 8
        while (sum ushr 16 != 0) sum = (sum and 0xFFFF) + (sum ushr 16)
        return sum.inv() and 0xFFFF
    }

    private fun startAsForeground() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID, "BlockIT site filter",
                    NotificationManager.IMPORTANCE_LOW
                )
            )
        }
        val notification: Notification = Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("BlockIT site filter active")
            .setContentText("Blocking locked websites on-device.")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID, notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun stopVpn() {
        running = false
        worker?.interrupt()
        worker = null
        try { tun?.close() } catch (e: Exception) {}
        tun = null
        EngineEvents.emit("vpn_stopped")
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        running = false
        try { tun?.close() } catch (e: Exception) {}
        super.onDestroy()
    }

    /**
     * Called by the OS when the user revokes VPN permission from Settings
     * (Settings > VPN > disconnect/forget), or another app's VPN takes over.
     * This is the authoritative signal that site blocking just went dark —
     * fire the alert right here rather than trying to detect it indirectly.
     */
    override fun onRevoke() {
        DebugLog.log(this, "VPN", "onRevoke — VPN permission revoked, sending tamper alert")
        TamperAlertMailer.sendAlert(this, "vpn_revoked")
        EngineEvents.emit("vpn_stopped")
        super.onRevoke()
    }

    companion object {
        private const val CHANNEL_ID = "blockit_vpn"
        private const val NOTIFICATION_ID = 1002
        const val ACTION_STOP = "com.blockit.mobile.VPN_STOP"
        const val ACTION_REFRESH = "com.blockit.mobile.VPN_REFRESH"

        fun start(context: Context) {
            val intent = Intent(context, BlockVpnService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.startService(
                Intent(context, BlockVpnService::class.java).setAction(ACTION_STOP)
            )
        }

        /** Nudge the running VPN to re-read the locked-domain set immediately. */
        fun refresh(context: Context) {
            if (!EngineForegroundService.isRunning) return
            context.startService(
                Intent(context, BlockVpnService::class.java).setAction(ACTION_REFRESH)
            )
        }
    }
}
