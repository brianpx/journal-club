(function () {
    var root = document.documentElement;

    function apply(theme) {
        root.classList.toggle('dark', theme === 'dark');
        try { localStorage.setItem('theme', theme); } catch (e) {}
    }

    function toggle() {
        apply(root.classList.contains('dark') ? 'light' : 'dark');
    }

    document.querySelectorAll('[data-theme-toggle]').forEach(function (btn) {
        btn.addEventListener('click', toggle);
    });
})();
