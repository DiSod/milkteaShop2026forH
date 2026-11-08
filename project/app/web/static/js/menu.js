/* 点单页交互（可选增强：禁用 JS 时表单照常可提交）
 *
 * 三块能力：
 *   1. 二级菜单对话框：选杯型/数量/加料时实时算「小计」；点「加入订单」把数量
 *      置为 1（若还是 0）并关闭；关闭后卡片上显示「已选 N 杯」
 *   2. 底部悬浮栏：常驻显示「N 杯 · 合计 ¥X」，数量为 0 时禁用提交
 *   3. 购物车面板（底部弹出）：列出已选饮品，可 −/+ 改数量、可点「改」回到
 *      该饮品的对话框、可清空
 *
 * 全部状态都存在对话框里的原生表单控件上（qty select），脚本不另存一份，
 * 因此提交给服务端的始终是那套平行列表，_parse_items 一行不用改。
 */
(function () {
  "use strict";

  var modals = Array.prototype.slice.call(document.querySelectorAll("[data-drink-modal]"));
  var bar = document.querySelector("[data-cart-bar]");
  var countEl = document.querySelector("[data-cart-count]");
  var totalEl = document.querySelector("[data-cart-total]");
  var submitBtns = Array.prototype.slice.call(document.querySelectorAll("[data-cart-submit]"));
  var listEl = document.querySelector("[data-cart-list]");
  var emptyEl = document.querySelector("[data-cart-empty]");
  var clearBtn = document.querySelector("[data-cart-clear]");

  if (!modals.length) return;

  function money(n) {
    return "¥" + n.toFixed(2);
  }

  function qty(modal) {
    var sel = modal.querySelector("[data-qty]");
    return sel ? parseInt(sel.value, 10) || 0 : 0;
  }

  function setQty(modal, n) {
    var sel = modal.querySelector("[data-qty]");
    if (!sel) return;
    var max = sel.options.length - 1;
    n = Math.max(0, Math.min(max, n));
    sel.value = String(n);
    sel.dispatchEvent(new Event("change", { bubbles: true }));
  }

  function chosenCup(modal) {
    var sel = modal.querySelector("[data-cup]");
    if (!sel) return null;
    return sel.options[sel.selectedIndex] || null;
  }

  function cupPrice(modal) {
    var opt = chosenCup(modal);
    return opt ? parseFloat(opt.dataset.price || "0") : 0;
  }

  function cupLabel(modal) {
    var opt = chosenCup(modal);
    if (!opt) return "";
    return opt.textContent.split("·")[0].trim();
  }

  function toppingTotal(modal) {
    var sum = 0;
    modal.querySelectorAll("[data-topping]:checked").forEach(function (box) {
      sum += parseFloat(box.dataset.price || "0");
    });
    return sum;
  }

  function toppingCount(modal) {
    return modal.querySelectorAll("[data-topping]:checked").length;
  }

  function unitPrice(modal) {
    return cupPrice(modal) + toppingTotal(modal);
  }

  function title(modal) {
    var el = modal.querySelector(".modal-title");
    return el ? el.textContent.trim() : "";
  }

  function refreshSubtotal(modal) {
    var out = modal.querySelector("[data-subtotal]");
    if (!out) return;
    var each = unitPrice(modal);
    var n = qty(modal);
    out.textContent = n > 0
      ? "小计 " + money(each * n) + "（" + money(each) + " × " + n + "）"
      : "请选择数量";
  }

  function refreshCard(modal) {
    var card = document.querySelector('[data-bs-target="#' + modal.id + '"]');
    if (!card) return;
    var picked = card.querySelector("[data-picked]");
    if (!picked) return;
    var n = qty(modal);
    if (n > 0) {
      picked.textContent = "已选 " + n + " 杯";
      picked.hidden = false;
      card.classList.add("is-picked");
    } else {
      picked.hidden = true;
      card.classList.remove("is-picked");
    }
  }

  function cartLine(modal) {
    var n = qty(modal);
    var extra = toppingCount(modal);
    var label = title(modal);

    var row = document.createElement("div");
    row.className = "cart-line";

    var main = document.createElement("div");
    main.className = "cart-line-main";
    var name = document.createElement("span");
    name.className = "cart-line-name";
    name.textContent = label;
    var sub = document.createElement("span");
    sub.className = "cart-line-sub";
    sub.textContent = cupLabel(modal) + " · " + n + " 杯" + (extra ? " · 加料 " + extra + " 份" : "");
    main.appendChild(name);
    main.appendChild(sub);

    var right = document.createElement("div");
    right.className = "cart-line-right";
    var price = document.createElement("span");
    price.className = "cart-line-price";
    price.textContent = money(unitPrice(modal) * n);
    right.appendChild(price);

    [
      { text: "−", cls: "btn-outline-secondary", aria: "减少 " + label + " 的数量", step: -1 },
      { text: "+", cls: "btn-outline-secondary", aria: "增加 " + label + " 的数量", step: 1 }
    ].forEach(function (spec) {
      var b = document.createElement("button");
      b.type = "button";
      b.className = "btn btn-sm " + spec.cls;
      b.textContent = spec.text;
      b.setAttribute("aria-label", spec.aria);
      b.addEventListener("click", function () {
        setQty(modal, qty(modal) + spec.step);
        refreshSubtotal(modal);
        renderCart();
      });
      right.appendChild(b);
    });

    var edit = document.createElement("button");
    edit.type = "button";
    edit.className = "btn btn-sm btn-outline-primary";
    edit.textContent = "改";
    edit.setAttribute("aria-label", "修改 " + label + " 的规格");
    edit.addEventListener("click", function () {
      var sheet = document.getElementById("cartSheet");
      if (sheet && window.bootstrap && window.bootstrap.Offcanvas) {
        var inst = window.bootstrap.Offcanvas.getInstance(sheet);
        if (inst) inst.hide();
      }
      window.bootstrap.Modal.getOrCreateInstance(modal).show();
    });
    right.appendChild(edit);

    row.appendChild(main);
    row.appendChild(right);
    return row;
  }

  function renderCart() {
    var chosen = modals.filter(function (m) { return qty(m) > 0; });
    var cups = chosen.reduce(function (s, m) { return s + qty(m); }, 0);
    var total = chosen.reduce(function (s, m) { return s + unitPrice(m) * qty(m); }, 0);

    modals.forEach(refreshCard);

    if (countEl) countEl.textContent = cups + " 杯";
    if (totalEl) totalEl.textContent = money(total);
    submitBtns.forEach(function (b) { b.disabled = cups === 0; });
    if (bar) bar.classList.toggle("is-empty", cups === 0);

    if (listEl) {
      listEl.innerHTML = "";
      chosen.forEach(function (modal) { listEl.appendChild(cartLine(modal)); });
    }
    if (emptyEl) emptyEl.hidden = chosen.length > 0;
  }

  modals.forEach(function (modal) {
    modal.addEventListener("change", function () {
      refreshSubtotal(modal);
      renderCart();
    });
    modal.addEventListener("hidden.bs.modal", function () {
      refreshCard(modal);
      renderCart();
    });

    var add = modal.querySelector("[data-add]");
    if (add) {
      add.addEventListener("click", function () {
        if (qty(modal) === 0) setQty(modal, 1);
        refreshSubtotal(modal);
        if (window.bootstrap && window.bootstrap.Modal) {
          window.bootstrap.Modal.getOrCreateInstance(modal).hide();
        }
        renderCart();
      });
    }

    refreshSubtotal(modal);
  });

  if (clearBtn) {
    clearBtn.addEventListener("click", function () {
      modals.forEach(function (m) {
        var sel = m.querySelector("[data-qty]");
        if (sel) {
          sel.value = "0";
          sel.dispatchEvent(new Event("change", { bubbles: true }));
        }
        refreshSubtotal(m);
      });
      renderCart();
    });
  }

  if (bar) bar.hidden = false;
  document.body.classList.add("has-cart-bar");
  document.querySelectorAll("[data-page-submit]").forEach(function (el) {
    el.hidden = true;          /* 有悬浮栏就不再需要页面底部那颗按钮 */
  });

  renderCart();
})();
