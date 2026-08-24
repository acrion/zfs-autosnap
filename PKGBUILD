# Maintainer: Stefan Zipproth <s.zipproth@ditana.org>

pkgname=zfs-autosnap
pkgver=1.03
pkgrel=1
pkgdesc="zfs auto-snapshot script which runs before package upgrade using Pacman hook."
arch=("any")
url="https://github.com/acrion/zfs-autosnap"
license=('AGPL-3.0-or-later')
depends=('zfs-utils')
checkdepends=('bats')
source=(
    00-zfs-autosnap.hook
    zfs-autosnap.conf
    zfs-autosnap
    LICENSE
    lock-handling.bats
)
backup=('etc/zfs-autosnap.conf')
md5sums=(
    'SKIP'
    'SKIP'
    'SKIP'
    'SKIP'
    'SKIP'
)

check() {
    bats "${srcdir}/lock-handling.bats"
}

package() {
    install -Dm644 00-zfs-autosnap.hook ${pkgdir}/usr/share/libalpm/hooks/00-zfs-autosnap.hook
    install -Dm644 zfs-autosnap.conf ${pkgdir}/etc/zfs-autosnap.conf
    install -Dm755 zfs-autosnap ${pkgdir}/usr/bin/zfs-autosnap
    install -Dm644 LICENSE ${pkgdir}/usr/share/licenses/${pkgname}/LICENSE
}
