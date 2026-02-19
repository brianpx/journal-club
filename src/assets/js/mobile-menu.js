(function () {
    var menuButton = document.getElementById('menuButton');
    var mobileMenu = document.getElementById('mobile-menu');
    var closeMenu = document.getElementById('closeMenu');
    var menuBackdrop = document.getElementById('menuBackdrop');
    if (!menuButton || !mobileMenu) return;

    var lastFocus = null;

    function open() {
        lastFocus = document.activeElement;
        mobileMenu.classList.remove('hidden');
        menuButton.setAttribute('aria-expanded', 'true');
        if (closeMenu) closeMenu.focus();
        document.body.style.overflow = 'hidden';
    }

    function close() {
        mobileMenu.classList.add('hidden');
        menuButton.setAttribute('aria-expanded', 'false');
        document.body.style.overflow = '';
        if (lastFocus) lastFocus.focus();
    }

    menuButton.addEventListener('click', open);
    if (closeMenu) closeMenu.addEventListener('click', close);
    if (menuBackdrop) menuBackdrop.addEventListener('click', close);

    mobileMenu.querySelectorAll('a').forEach(function (link) {
        link.addEventListener('click', close);
    });

    document.addEventListener('keydown', function (e) {
        if (e.key === 'Escape' && !mobileMenu.classList.contains('hidden')) {
            close();
        }
    });

    mobileMenu.addEventListener('click', function (e) {
        if (e.target === mobileMenu || e.target.getAttribute('aria-hidden') === 'true') {
            close();
        }
    });
})();
