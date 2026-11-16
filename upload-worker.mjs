import { timingSafeEqual } from 'node:crypto'

const maxSize = 90 * 1024 * 1024
const filename = /^\/neon_[0-9]{8}T[0-9]{6}Z_(?:[0-9]+|manual)_[0-9]+\.dump$/
const encoder = new TextEncoder()

export default {
  async fetch(request, env) {
    if (request.method !== 'PUT') return new Response(null, { status: 405 })
    const received = encoder.encode(request.headers.get('Authorization') ?? '')
    const expected = encoder.encode('Bearer ' + env.BACKUP_UPLOAD_SECRET)
    if (!env.BACKUP_UPLOAD_SECRET || received.length !== expected.length ||
        !timingSafeEqual(received, expected)) return new Response(null, { status: 401 })

    const { pathname } = new URL(request.url)
    const length = Number(request.headers.get('Content-Length'))
    const checksum = request.headers.get('X-Backup-SHA256') ?? ''
    if (!filename.test(pathname) || !/^[a-f0-9]{64}$/.test(checksum) || !request.body ||
        !Number.isSafeInteger(length) || length < 6) return new Response(null, { status: 400 })
    if (length > maxSize) return new Response(null, { status: 413 })

    const key = 'postgresql' + pathname
    const stored = await env.BACKUPS.put(key, request.body, {
      sha256: checksum,
      onlyIf: { etagDoesNotMatch: '*' },
      httpMetadata: { contentType: 'application/octet-stream' },
      customMetadata: { sha256: checksum },
    })
    if (!stored) {
      const previous = await env.BACKUPS.head(key)
      if (previous?.customMetadata?.sha256 !== checksum || previous?.size !== length) {
        return new Response(null, { status: 409 })
      }
    }
    return new Response(null, { status: stored ? 201 : 204 })
  },
}
