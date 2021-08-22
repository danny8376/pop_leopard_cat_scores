// minify with UglifyJS 3
// manually replace map/unshift back after minified
// also replace "string" "object"

(function() {
    var R = 'input is invalid type';
    var AB = window.ArrayBuffer;
    var U8A = Uint8Array;
    var U32A = Uint32Array;
    var E = [128, 32768, 8388608, -2147483648];
    var S = [0, 8, 16, 24];
    var T = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'.split('');
    var sT = setTimeout;
    var _cCA = 'charCodeAt';
    var _buffer = 'buffer';
    var _s = 'string';
    var _o = 'object';
    var m = 'map';
    var u = 'unshift';

    var AiA = Array.isArray;

    var blocks = [],
        buffer8;

    var time = function() { return new Date() };

    var last = time();

    if (AB) {
        var buffer = new AB(68);
        buffer8 = new U8A(buffer);
        blocks = new U32A(buffer);
    }

    if (!AiA) {
        AiA = function(obj) {
            return Object.prototype.toString.call(obj) === '[object Array]';
        };
    }

    if (AB) {
        var ABiV = AB.isView;
        if (!ABiV) {
            ABiV = function(obj) {
                return typeof obj === _o && obj[_buffer] && obj[_buffer].constructor === AB;
            };
        }
    }

    /**
     * a => lastByteIndex
     * b => buffer8
     * d => digest
     * f => finalize
     * h => hash
     * i => bytes
     * j => hBytes
     * l => blocks
     * m => fd
     * n => hed
     * o
     * r => first
     * s => start
     * u => update
     * w => h0
     * x => h1
     * y => h2
     * z => h3
     */

    /**
     * H class
     * @class H
     * @description This is internal class.
     * @see {@link md5.create}
     */
    function H(sharedMemory) {
        if (sharedMemory) {
            blocks[0] = blocks[16] = blocks[1] = blocks[2] = blocks[3] =
                blocks[4] = blocks[5] = blocks[6] = blocks[7] =
                blocks[8] = blocks[9] = blocks[10] = blocks[11] =
                blocks[12] = blocks[13] = blocks[14] = blocks[15] = 0;
            this.l = blocks;
            this.b = buffer8;
        } else {
            if (AB) {
                var buffer = new AB(68);
                this.b = new U8A(buffer);
                this.l = new U32A(buffer);
            } else {
                this.l = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
            }
        }
        this.w = this.x = this.y = this.z = this.s = this.i = this.j = 0;
        this.m = this.n = false;
        this.r = true;
    }
    
    var H_prototype = H.prototype;

    /**
     * @method u
     * @memberof H
     * @instance
     * @description Update h
     * @param {String|Array|U8A|AB} message message to h
     * @returns {H} H object.
     * @see {@link md5.u}
     */
    H_prototype.u = function(message) {
        if (this.m) {
            return;
        }

        var notString, type = typeof message;
        if (type !== _s) {
            if (type === _o) {
                if (message === null) {
                    throw R;
                } else if (message.constructor === AB) {
                    message = new U8A(message);
                } else if (!AiA(message)) {
                    if (!AB || !ABiV(message)) {
                        throw R;
                    }
                }
            } else {
                throw R;
            }
            notString = true;
        }
        var code, index = 0,
            i, length = message.length,
            blocks = this.l;
        var buffer8 = this.b;

        while (index < length) {
            if (this.n) {
                this.n = false;
                blocks[0] = blocks[16];
                blocks[16] = blocks[1] = blocks[2] = blocks[3] =
                    blocks[4] = blocks[5] = blocks[6] = blocks[7] =
                    blocks[8] = blocks[9] = blocks[10] = blocks[11] =
                    blocks[12] = blocks[13] = blocks[14] = blocks[15] = 0;
            }

            if (notString) {
                if (AB) {
                    for (i = this.s; index < length && i < 64; ++index) {
                        buffer8[i++] = message[index];
                    }
                } else {
                    for (i = this.s; index < length && i < 64; ++index) {
                        blocks[i >> 2] |= message[index] << S[i++ & 3];
                    }
                }
            } else {
                if (AB) {
                    for (i = this.s; index < length && i < 64; ++index) {
                        code = message[_cCA](index);
                        if (code < 0x80) {
                            buffer8[i++] = code;
                        } else if (code < 0x800) {
                            buffer8[i++] = 0xc0 | (code >> 6);
                            buffer8[i++] = 0x80 | (code & 0x3f);
                        } else if (code < 0xd800 || code >= 0xe000) {
                            buffer8[i++] = 0xe0 | (code >> 12);
                            buffer8[i++] = 0x80 | ((code >> 6) & 0x3f);
                            buffer8[i++] = 0x80 | (code & 0x3f);
                        } else {
                            code = 0x10000 + (((code & 0x3ff) << 10) | (message[_cCA](++index) & 0x3ff));
                            buffer8[i++] = 0xf0 | (code >> 18);
                            buffer8[i++] = 0x80 | ((code >> 12) & 0x3f);
                            buffer8[i++] = 0x80 | ((code >> 6) & 0x3f);
                            buffer8[i++] = 0x80 | (code & 0x3f);
                        }
                    }
                } else {
                    for (i = this.s; index < length && i < 64; ++index) {
                        code = message[_cCA](index);
                        if (code < 0x80) {
                            blocks[i >> 2] |= code << S[i++ & 3];
                        } else if (code < 0x800) {
                            blocks[i >> 2] |= (0xc0 | (code >> 6)) << S[i++ & 3];
                            blocks[i >> 2] |= (0x80 | (code & 0x3f)) << S[i++ & 3];
                        } else if (code < 0xd800 || code >= 0xe000) {
                            blocks[i >> 2] |= (0xe0 | (code >> 12)) << S[i++ & 3];
                            blocks[i >> 2] |= (0x80 | ((code >> 6) & 0x3f)) << S[i++ & 3];
                            blocks[i >> 2] |= (0x80 | (code & 0x3f)) << S[i++ & 3];
                        } else {
                            code = 0x10000 + (((code & 0x3ff) << 10) | (message[_cCA](++index) & 0x3ff));
                            blocks[i >> 2] |= (0xf0 | (code >> 18)) << S[i++ & 3];
                            blocks[i >> 2] |= (0x80 | ((code >> 12) & 0x3f)) << S[i++ & 3];
                            blocks[i >> 2] |= (0x80 | ((code >> 6) & 0x3f)) << S[i++ & 3];
                            blocks[i >> 2] |= (0x80 | (code & 0x3f)) << S[i++ & 3];
                        }
                    }
                }
            }
            this.a = i;
            this.i += i - this.s;
            if (i >= 64) {
                this.s = i - 64;
                this.h();
                this.n = true;
            } else {
                this.s = i;
            }
        }
        if (this.i > 4294967295) {
            this.j += this.i / 4294967296 << 0;
            this.i = this.i % 4294967296;
        }
        return this;
    };

    H_prototype.f = function() {
        if (this.m) {
            return;
        }
        this.m = true;
        var blocks = this.l,
            i = this.a;
        blocks[i >> 2] |= E[i & 3];
        if (i >= 56) {
            if (!this.n) {
                this.h();
            }
            blocks[0] = blocks[16];
            blocks[16] = blocks[1] = blocks[2] = blocks[3] =
                blocks[4] = blocks[5] = blocks[6] = blocks[7] =
                blocks[8] = blocks[9] = blocks[10] = blocks[11] =
                blocks[12] = blocks[13] = blocks[14] = blocks[15] = 0;
        }
        blocks[14] = this.i << 3;
        blocks[15] = this.j << 3 | this.i >>> 29;
        this.h();
    };

    H_prototype.h = function() {
        var a, b, c, d, bc, da, blocks = this.l;

        if (this.r) {
            a = blocks[0] - 680876937;
            a = (a << 7 | a >>> 25) - 271733879 << 0;
            d = (-1732584194 ^ a & 2004318071) + blocks[1] - 117830708;
            d = (d << 12 | d >>> 20) + a << 0;
            c = (-271733879 ^ (d & (a ^ -271733879))) + blocks[2] - 1126478375;
            c = (c << 17 | c >>> 15) + d << 0;
            b = (a ^ (c & (d ^ a))) + blocks[3] - 1316259209;
            b = (b << 22 | b >>> 10) + c << 0;
        } else {
            a = this.w;
            b = this.x;
            c = this.y;
            d = this.z;
            a += (d ^ (b & (c ^ d))) + blocks[0] - 680876936;
            a = (a << 7 | a >>> 25) + b << 0;
            d += (c ^ (a & (b ^ c))) + blocks[1] - 389564586;
            d = (d << 12 | d >>> 20) + a << 0;
            c += (b ^ (d & (a ^ b))) + blocks[2] + 606105819;
            c = (c << 17 | c >>> 15) + d << 0;
            b += (a ^ (c & (d ^ a))) + blocks[3] - 1044525330;
            b = (b << 22 | b >>> 10) + c << 0;
        }

        a += (d ^ (b & (c ^ d))) + blocks[4] - 176418897;
        a = (a << 7 | a >>> 25) + b << 0;
        d += (c ^ (a & (b ^ c))) + blocks[5] + 1200080426;
        d = (d << 12 | d >>> 20) + a << 0;
        c += (b ^ (d & (a ^ b))) + blocks[6] - 1473231341;
        c = (c << 17 | c >>> 15) + d << 0;
        b += (a ^ (c & (d ^ a))) + blocks[7] - 45705983;
        b = (b << 22 | b >>> 10) + c << 0;
        a += (d ^ (b & (c ^ d))) + blocks[8] + 1770035416;
        a = (a << 7 | a >>> 25) + b << 0;
        d += (c ^ (a & (b ^ c))) + blocks[9] - 1958414417;
        d = (d << 12 | d >>> 20) + a << 0;
        c += (b ^ (d & (a ^ b))) + blocks[10] - 42063;
        c = (c << 17 | c >>> 15) + d << 0;
        b += (a ^ (c & (d ^ a))) + blocks[11] - 1990404162;
        b = (b << 22 | b >>> 10) + c << 0;
        a += (d ^ (b & (c ^ d))) + blocks[12] + 1804603682;
        a = (a << 7 | a >>> 25) + b << 0;
        d += (c ^ (a & (b ^ c))) + blocks[13] - 40341101;
        d = (d << 12 | d >>> 20) + a << 0;
        c += (b ^ (d & (a ^ b))) + blocks[14] - 1502002290;
        c = (c << 17 | c >>> 15) + d << 0;
        b += (a ^ (c & (d ^ a))) + blocks[15] + 1236535329;
        b = (b << 22 | b >>> 10) + c << 0;
        a += (c ^ (d & (b ^ c))) + blocks[1] - 165796510;
        a = (a << 5 | a >>> 27) + b << 0;
        d += (b ^ (c & (a ^ b))) + blocks[6] - 1069501632;
        d = (d << 9 | d >>> 23) + a << 0;
        c += (a ^ (b & (d ^ a))) + blocks[11] + 643717713;
        c = (c << 14 | c >>> 18) + d << 0;
        b += (d ^ (a & (c ^ d))) + blocks[0] - 373897302;
        b = (b << 20 | b >>> 12) + c << 0;
        a += (c ^ (d & (b ^ c))) + blocks[5] - 701558691;
        a = (a << 5 | a >>> 27) + b << 0;
        d += (b ^ (c & (a ^ b))) + blocks[10] + 38016083;
        d = (d << 9 | d >>> 23) + a << 0;
        c += (a ^ (b & (d ^ a))) + blocks[15] - 660478335;
        c = (c << 14 | c >>> 18) + d << 0;
        b += (d ^ (a & (c ^ d))) + blocks[4] - 405537848;
        b = (b << 20 | b >>> 12) + c << 0;
        a += (c ^ (d & (b ^ c))) + blocks[9] + 568446438;
        a = (a << 5 | a >>> 27) + b << 0;
        d += (b ^ (c & (a ^ b))) + blocks[14] - 1019803690;
        d = (d << 9 | d >>> 23) + a << 0;
        c += (a ^ (b & (d ^ a))) + blocks[3] - 187363961;
        c = (c << 14 | c >>> 18) + d << 0;
        b += (d ^ (a & (c ^ d))) + blocks[8] + 1163531501;
        b = (b << 20 | b >>> 12) + c << 0;
        a += (c ^ (d & (b ^ c))) + blocks[13] - 1444681467;
        a = (a << 5 | a >>> 27) + b << 0;
        d += (b ^ (c & (a ^ b))) + blocks[2] - 51403784;
        d = (d << 9 | d >>> 23) + a << 0;
        c += (a ^ (b & (d ^ a))) + blocks[7] + 1735328473;
        c = (c << 14 | c >>> 18) + d << 0;
        b += (d ^ (a & (c ^ d))) + blocks[12] - 1926607734;
        b = (b << 20 | b >>> 12) + c << 0;
        bc = b ^ c;
        a += (bc ^ d) + blocks[5] - 378558;
        a = (a << 4 | a >>> 28) + b << 0;
        d += (bc ^ a) + blocks[8] - 2022574463;
        d = (d << 11 | d >>> 21) + a << 0;
        da = d ^ a;
        c += (da ^ b) + blocks[11] + 1839030562;
        c = (c << 16 | c >>> 16) + d << 0;
        b += (da ^ c) + blocks[14] - 35309556;
        b = (b << 23 | b >>> 9) + c << 0;
        bc = b ^ c;
        a += (bc ^ d) + blocks[1] - 1530992060;
        a = (a << 4 | a >>> 28) + b << 0;
        d += (bc ^ a) + blocks[4] + 1272893353;
        d = (d << 11 | d >>> 21) + a << 0;
        da = d ^ a;
        c += (da ^ b) + blocks[7] - 155497632;
        c = (c << 16 | c >>> 16) + d << 0;
        b += (da ^ c) + blocks[10] - 1094730640;
        b = (b << 23 | b >>> 9) + c << 0;
        bc = b ^ c;
        a += (bc ^ d) + blocks[13] + 681279174;
        a = (a << 4 | a >>> 28) + b << 0;
        d += (bc ^ a) + blocks[0] - 358537222;
        d = (d << 11 | d >>> 21) + a << 0;
        da = d ^ a;
        c += (da ^ b) + blocks[3] - 722521979;
        c = (c << 16 | c >>> 16) + d << 0;
        b += (da ^ c) + blocks[6] + 76029189;
        b = (b << 23 | b >>> 9) + c << 0;
        bc = b ^ c;
        a += (bc ^ d) + blocks[9] - 640364487;
        a = (a << 4 | a >>> 28) + b << 0;
        d += (bc ^ a) + blocks[12] - 421815835;
        d = (d << 11 | d >>> 21) + a << 0;
        da = d ^ a;
        c += (da ^ b) + blocks[15] + 530742520;
        c = (c << 16 | c >>> 16) + d << 0;
        b += (da ^ c) + blocks[2] - 995338651;
        b = (b << 23 | b >>> 9) + c << 0;
        a += (c ^ (b | ~d)) + blocks[0] - 198630844;
        a = (a << 6 | a >>> 26) + b << 0;
        d += (b ^ (a | ~c)) + blocks[7] + 1126891415;
        d = (d << 10 | d >>> 22) + a << 0;
        c += (a ^ (d | ~b)) + blocks[14] - 1416354905;
        c = (c << 15 | c >>> 17) + d << 0;
        b += (d ^ (c | ~a)) + blocks[5] - 57434055;
        b = (b << 21 | b >>> 11) + c << 0;
        a += (c ^ (b | ~d)) + blocks[12] + 1700485571;
        a = (a << 6 | a >>> 26) + b << 0;
        d += (b ^ (a | ~c)) + blocks[3] - 1894986606;
        d = (d << 10 | d >>> 22) + a << 0;
        c += (a ^ (d | ~b)) + blocks[10] - 1051523;
        c = (c << 15 | c >>> 17) + d << 0;
        b += (d ^ (c | ~a)) + blocks[1] - 2054922799;
        b = (b << 21 | b >>> 11) + c << 0;
        a += (c ^ (b | ~d)) + blocks[8] + 1873313359;
        a = (a << 6 | a >>> 26) + b << 0;
        d += (b ^ (a | ~c)) + blocks[15] - 30611744;
        d = (d << 10 | d >>> 22) + a << 0;
        c += (a ^ (d | ~b)) + blocks[6] - 1560198380;
        c = (c << 15 | c >>> 17) + d << 0;
        b += (d ^ (c | ~a)) + blocks[13] + 1309151649;
        b = (b << 21 | b >>> 11) + c << 0;
        a += (c ^ (b | ~d)) + blocks[4] - 145523070;
        a = (a << 6 | a >>> 26) + b << 0;
        d += (b ^ (a | ~c)) + blocks[11] - 1120210379;
        d = (d << 10 | d >>> 22) + a << 0;
        c += (a ^ (d | ~b)) + blocks[2] + 718787259;
        c = (c << 15 | c >>> 17) + d << 0;
        b += (d ^ (c | ~a)) + blocks[9] - 343485551;
        b = (b << 21 | b >>> 11) + c << 0;

        if (this.r) {
            this.w = a + 1732584193 << 0;
            this.x = b - 271733879 << 0;
            this.y = c - 1732584194 << 0;
            this.z = d + 271733878 << 0;
            this.r = false;
        } else {
            this.w = this.w + a << 0;
            this.x = this.x + b << 0;
            this.y = this.y + c << 0;
            this.z = this.z + d << 0;
        }
    };

    /**
     * @method d
     * @memberof H
     * @instance
     * @description Output h as bytes array
     * @returns {Array} Bytes array
     * @see {@link md5.d}
     * @example
     * h.d();
     */
    H_prototype.d = function() {
        this.f();

        var h0 = this.w,
            h1 = this.x,
            h2 = this.y;
        return [
            h0 & 0xFF, (h0 >> 8) & 0xFF, (h0 >> 16) & 0xFF, (h0 >> 24) & 0xFF,
            h1 & 0xFF, (h1 >> 8) & 0xFF, (h1 >> 16) & 0xFF, (h1 >> 24) & 0xFF,
            h2 & 0xFF
        ];
    };

    /**
     * @method base64
     * @memberof H
     * @instance
     * @description Output h as base64 string
     * @returns {String} base64 string
     * @see {@link md5.base64}
     * @example
     * h.base64();
     */
    H_prototype.o = function() {
        var v1, v2, v3, str = '',
            bytes = this.d();
        for (var i = 0; i < 9;) {
            v1 = bytes[i++];
            v2 = bytes[i++];
            v3 = bytes[i++];
            str += T[v1 >>> 2] +
                T[(v1 << 4 | v2 >>> 4) & 63] +
                T[(v2 << 2 | v3 >>> 6) & 63] +
                T[v3 & 63];
        }
        return str;
    };

    window.hash = function(h, a, c, e, dbg) {
        var now = time();
        var llock = (now - last) < 2.5;
        last = now;
        r = [-1, 0, 1][m](function(d) {
            var s = llock ? (a + "|" + c + "|" + (e + d) + "|" + h) : (h + "|" + (e + d) + "|" + c + "|" + a);
            return new H(true).u(s).o();
        });
        r[u](a);
        return r;
    };
})();
