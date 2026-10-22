chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.create({
    id: "birdy-close-reading",
    title: "Birdy 精读",
    contexts: ["selection"]
  });
});

chrome.contextMenus.onClicked.addListener((info, tab) => {
  if (info.menuItemId !== "birdy-close-reading") return;
  const text = (info.selectionText || "").trim();
  if (!text) return;

  const target = new URL("birdy://close-reading");
  target.searchParams.set("text", Array.from(text).slice(0, 5000).join(""));
  if (tab?.url && /^https?:\/\//i.test(tab.url)) target.searchParams.set("url", tab.url);

  const launchPage = new URL(chrome.runtime.getURL("launch.html"));
  launchPage.searchParams.set("target", target.toString());
  chrome.tabs.create({ url: launchPage.toString(), active: false });
});
