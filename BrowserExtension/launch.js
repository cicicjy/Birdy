const target = new URLSearchParams(location.search).get("target");
const fallback = document.getElementById("fallback");

if (target && target.startsWith("birdy://close-reading?")) {
  fallback.href = target;
  location.href = target;
  window.setTimeout(() => window.close(), 1800);
} else {
  document.body.textContent = "Birdy 没有收到这段文字，请返回网页重新选择后再试。";
}
