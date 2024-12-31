# Maintainer: Stefan Zipproth <s.zipproth@ditana.org>

pkgname=zfs-autosnap
pkgver=1.02
pkgrel=1
pkgdesc="zfs auto-snapshot script which runs before package upgrade using Pacman hook."
arch=("any")
url="https://gitlab.com/acrion/zfs-autosnap"
license=('AGPL-3.0-or-later')
depends=('zfs-utils')
source=(
    00-zfs-autosnap.hook
    zfs-autosnap.conf
    zfs-autosnap
    LICENSE
)
backup=('etc/zfs-autosnap.conf')
md5sums=(
    'SKIP'
    'SKIP'
    'SKIP'
    'SKIP'
)

package() {
    install -Dm644 00-zfs-autosnap.hook ${pkgdir}/usr/share/libalpm/hooks/00-zfs-autosnap.hook
    install -Dm644 zfs-autosnap.conf ${pkgdir}/etc/zfs-autosnap.conf
    install -Dm755 zfs-autosnap ${pkgdir}/usr/bin/zfs-autosnap
    install -Dm644 LICENSE ${pkgdir}/usr/share/licenses/${pkgname}/LICENSE
}
 
