// Copy to clipboard for all code blocks
document.querySelectorAll('pre').forEach(pre => {
  const btn = document.createElement('button');
  btn.className = 'copy-btn';
  btn.textContent = 'Copy';
  pre.style.position = 'relative';
  pre.appendChild(btn);
  btn.addEventListener('click', () => {
    const code = pre.querySelector('code')?.textContent || pre.textContent;
    navigator.clipboard.writeText(code.replace('Copy', '').trim()).then(() => {
      btn.textContent = 'Copied!';
      setTimeout(() => btn.textContent = 'Copy', 2000);
    });
  });
});

// Active nav link
const path = location.pathname.split('/').pop() || 'index.html';
document.querySelectorAll('nav a').forEach(a => {
  if (a.getAttribute('href') === path) a.classList.add('active');
});

// Mobile nav toggle
const hamburger = document.getElementById('hamburger');
const navMenu = document.getElementById('nav-menu');
if (hamburger && navMenu) {
  hamburger.addEventListener('click', () => navMenu.classList.toggle('open'));
}
