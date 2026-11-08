/* 点单页的二级菜单交互（可选增强：禁用 JS 时表单仍可提交）。
 *
 * 只做三件事：
 *   1. 对话框里选杯型/数量/加料时，实时算「小计」
 *   2. 点「加入订单」时，数量若还是 0 就置为 1，然后关闭对话框
 *   3. 关闭对话框后，把卡片右上角更新为「已选 N 杯」
 * 表单契约（平行列表）由服务端解析，脚本不构造任何提交数据。
 */
(function () {
  "use strict";

  function cups(modal) {
    return modal.querySelector("[data-cup]");
  }

  function cupPrice(modal) {
    var sel = cups(modal);
    if (!sel) return 0;
    var opt = sel.options[sel.selectedIndex];
    return opt ? parseFloat(opt.dataset.price || "0") : 0;
  }

  function toppingTotal(modal) {
    var sum = 0;
    modal.querySelectorAll("[data-topping]:checked").forEach(function (box) {
      sum += parseFloat(box.dataset.price || "0");
    });
    return sum;
  }

  function qty(modal) {
    var sel = modal.querySelector("[data-qty]");
    return sel ? parseInt(sel.value, 10) || 0 : 0;
  }

  function money(n) {
    return "¥" + n.toFixed(2);
  }

  function refreshSubtotal(modal) {
    var out = modal.querySelector("[data-subtotal]");
    if (!out) return;
    var each = cupPrice(modal) + toppingTotal(modal);
    var n = qty(modal);
    out.textContent = n > 0
      ? "小计 " + money(each * n) + "（" + money(each) + " × " + n + "）"
      : "请选择数量";
  }

  function refreshCard(modal) {
    var id = modal.id;
    var card = document.querySelector('[data-bs-target="#' + id + '"]');
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

  document.querySelectorAll("[data-drink-modal]").forEach(function (modal) {
    modal.addEventListener("change", function () { refreshSubtotal(modal); });
    modal.addEventListener("hidden.bs.modal", function () { refreshCard(modal); });

    var add = modal.querySelector("[data-add]");
    if (add) {
      add.addEventListener("click", function () {
        var sel = modal.querySelector("[data-qty]");
        if (sel && (parseInt(sel.value, 10) || 0) === 0) {
          sel.value = "1";
          refreshSubtotal(modal);
        }
        refreshCard(modal);
        if (window.bootstrap && window.bootstrap.Modal) {
          window.bootstrap.Modal.getOrCreateInstance(modal).hide();
        }
      });
    }

    refreshSubtotal(modal);
    refreshCard(modal);
  });
})();
