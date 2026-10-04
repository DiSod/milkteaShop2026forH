"""
奶茶店经营数据库 (茶颜小铺 · 单店)
仿真造数引擎 (generate_seed.py)
用于生成 17 张核心表的高保真业务数据，严格保证进销存台账自洽与物理约束。

进销存平衡式:
期初库存 + 采购入库 - 销售配方耗用 - 打烊报损 = 期末库存
全时段约束: qty_on_hand >= 0
"""

import os
import sys
import random
import argparse
from datetime import datetime, date, timedelta
from typing import List, Dict, Any, Tuple, Optional

# 解决 Windows 控制台编码问题
if sys.stdout.encoding != 'utf-8':
    try:
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
        sys.stderr.reconfigure(encoding='utf-8', errors='replace')
    except Exception:
        pass

# 固定全局随机种子，确保可复现性
DEFAULT_SEED = 2026

# ==============================================================================
# 1. 静态主数据定义 (Master Data)
# ==============================================================================

# 1.1 员工 tbl_employee (5人)
EMPLOYEES = [
    {"employee_id": 1, "employee_code": "E001", "employee_name": "张伟", "position": "MANAGER", "hire_date": "2024-03-01", "is_active": 1},
    {"employee_id": 2, "employee_code": "E002", "employee_name": "李娜", "position": "CASHIER", "hire_date": "2024-06-15", "is_active": 1},
    {"employee_id": 3, "employee_code": "E003", "employee_name": "王强", "position": "MAKER",   "hire_date": "2025-01-10", "is_active": 1},
    {"employee_id": 4, "employee_code": "E004", "employee_name": "赵敏", "position": "MAKER",   "hire_date": "2025-03-20", "is_active": 1},
    {"employee_id": 5, "employee_code": "E005", "employee_name": "陈静", "position": "STOCKER", "hire_date": "2025-05-06", "is_active": 1},
]

# 1.2 商品品类 tbl_product_category (5类)
CATEGORIES = [
    {"category_id": 1, "parent_category_id": None, "category_code": "C01", "category_name": "经典奶茶",     "sort_no": 1, "is_active": 1},
    {"category_id": 2, "parent_category_id": None, "category_code": "C02", "category_name": "水果茶",       "sort_no": 2, "is_active": 1},
    {"category_id": 3, "parent_category_id": None, "category_code": "C03", "category_name": "纯茶",         "sort_no": 3, "is_active": 1},
    {"category_id": 4, "parent_category_id": None, "category_code": "C04", "category_name": "冰淇淋与奶昔", "sort_no": 4, "is_active": 1},
    {"category_id": 5, "parent_category_id": None, "category_code": "C05", "category_name": "季节限定",     "sort_no": 5, "is_active": 1},
]

# 1.3 供应商 tbl_supplier (3家)
SUPPLIERS = [
    {"supplier_id": 1, "supplier_code": "SUP01", "supplier_name": "晨光乳业",     "is_active": 1},
    {"supplier_id": 2, "supplier_code": "SUP02", "supplier_name": "闽南茶叶批发", "is_active": 1},
    {"supplier_id": 3, "supplier_code": "SUP03", "supplier_name": "佳益包材",     "is_active": 1},
]

# 1.4 规格选项 tbl_spec_option (11项，已移除废弃的 ANY 哨兵)
SPEC_OPTIONS = [
    {"spec_option_id": 1,  "spec_type": "CUP",   "spec_code": "M",       "spec_name": "中杯",     "extra_price": 0.00, "sort_no": 1},
    {"spec_option_id": 2,  "spec_type": "CUP",   "spec_code": "L",       "spec_name": "大杯",     "extra_price": 3.00, "sort_no": 2},
    # ⚠️ spec_option_id=3 ('ANY') 系 D-05a 废弃的哨兵，已从数据字典与数据库中彻底移除
    {"spec_option_id": 4,  "spec_type": "SUGAR", "spec_code": "NONE",    "spec_name": "无糖",     "extra_price": 0.00, "sort_no": 2},
    {"spec_option_id": 5,  "spec_type": "SUGAR", "spec_code": "S30",     "spec_name": "三分糖",   "extra_price": 0.00, "sort_no": 3},
    {"spec_option_id": 6,  "spec_type": "SUGAR", "spec_code": "S50",     "spec_name": "五分糖",   "extra_price": 0.00, "sort_no": 4},
    {"spec_option_id": 7,  "spec_type": "SUGAR", "spec_code": "S70",     "spec_name": "七分糖",   "extra_price": 0.00, "sort_no": 5},
    {"spec_option_id": 8,  "spec_type": "SUGAR", "spec_code": "FULL",    "spec_name": "全糖",     "extra_price": 0.00, "sort_no": 6},
    {"spec_option_id": 9,  "spec_type": "ICE",   "spec_code": "NO_ICE",  "spec_name": "去冰",     "extra_price": 0.00, "sort_no": 1},
    {"spec_option_id": 10, "spec_type": "ICE",   "spec_code": "LESS",    "spec_name": "少冰",     "extra_price": 0.00, "sort_no": 2},
    {"spec_option_id": 11, "spec_type": "ICE",   "spec_code": "NORMAL",  "spec_name": "正常冰",   "extra_price": 0.00, "sort_no": 3},
    {"spec_option_id": 12, "spec_type": "ICE",   "spec_code": "HOT",     "spec_name": "热饮",     "extra_price": 0.00, "sort_no": 4},
]

SPEC_MAP = {(item["spec_type"], item["spec_code"]): item["spec_option_id"] for item in SPEC_OPTIONS}

# 1.5 原料清单 tbl_ingredient (60种)
# 元组结构: (id, code, name, unit, spec, reorder_point, target_level, init_cost, default_supplier_id)
RAW_INGREDIENTS = [
    # A. 茶底 (6) -> 供应商 2 (闽南茶叶批发)
    (1,  "I001", "红茶（阿萨姆）", "g",  "500g/袋",   1000.0,   5000.0,  0.0620, 2),
    (2,  "I002", "茉莉绿茶",       "g",  "500g/袋",   1000.0,   5000.0,  0.0580, 2),
    (3,  "I003", "四季春茶",       "g",  "500g/袋",    800.0,   4000.0,  0.0650, 2),
    (4,  "I004", "乌龙茶",         "g",  "500g/袋",    500.0,   2500.0,  0.0700, 2),
    (5,  "I005", "伯爵红茶",       "g",  "500g/袋",    300.0,   1500.0,  0.0800, 2),
    (6,  "I006", "抹茶粉",         "g",  "100g/罐",    200.0,   1000.0,  0.1500, 2),

    # B. 奶基底 (5) -> 供应商 1 (晨光乳业)
    (7,  "I007", "植脂末（奶精）", "g",  "1kg/袋",    3000.0,  15000.0,  0.0220, 1),
    (8,  "I008", "纯牛奶",         "ml", "1L/盒",    30000.0, 100000.0,  0.0120, 1),
    (9,  "I009", "淡奶油",         "ml", "1L/盒",     1000.0,   5000.0,  0.0350, 1),
    (10, "I010", "炼乳",           "g",  "500g/罐",    500.0,   2500.0,  0.0280, 1),
    (11, "I011", "全脂奶粉",       "g",  "1kg/袋",     500.0,   2500.0,  0.0450, 1),

    # C. 糖与糖浆 (5) -> 供应商 2 (闽南茶叶批发)
    (12, "I012", "果糖（F60）",    "ml", "2.5kg/桶", 10000.0,  40000.0,  0.0185, 2),
    (13, "I013", "蔗糖浆",         "ml", "2.5kg/桶",  3000.0,  15000.0,  0.0200, 2),
    (14, "I014", "黑糖浆",         "ml", "1kg/罐",    1500.0,   6000.0,  0.0300, 2),
    (15, "I015", "蜂蜜",           "ml", "1kg/瓶",     500.0,   2000.0,  0.0400, 2),
    (16, "I016", "香草糖浆",       "ml", "750ml/瓶",   400.0,   1500.0,  0.0500, 2),

    # D. 小料 (10) -> 供应商 1 (晨光乳业)
    (17, "I017", "珍珠（生）",     "g",  "1kg/袋",    5000.0,  20000.0,  0.0110, 1),
    (18, "I018", "椰果",           "g",  "1kg/袋",    1500.0,   6000.0,  0.0120, 1),
    (19, "I019", "布丁粉",         "g",  "1kg/袋",    1000.0,   4000.0,  0.0250, 1),
    (20, "I020", "芋圆",           "g",  "1kg/袋",    1500.0,   6000.0,  0.0180, 1),
    (21, "I021", "西米",           "g",  "1kg/袋",     800.0,   3000.0,  0.0150, 1),
    (22, "I022", "蜜红豆",         "g",  "1kg/袋",    1000.0,   4000.0,  0.0160, 1),
    (23, "I023", "仙草冻",         "g",  "1kg/袋",     800.0,   3000.0,  0.0140, 1),
    (24, "I024", "啵啵脆",         "g",  "500g/袋",    600.0,   2500.0,  0.0320, 1),
    (25, "I025", "芋泥",           "g",  "1kg/袋",    1000.0,   4000.0,  0.0260, 1),
    (26, "I026", "燕麦",           "g",  "1kg/袋",     500.0,   2000.0,  0.0180, 1),

    # E. 鲜果 (7) -> 供应商 2 (闽南茶叶批发)
    (27, "I027", "柠檬",           "g",  "散装",      6000.0,  30000.0,  0.0120, 2),
    (28, "I028", "百香果",         "g",  "散装",      2000.0,  10000.0,  0.0240, 2),
    (29, "I029", "蜜桃",           "g",  "散装",      4500.0,  22500.0,  0.0200, 2),
    (30, "I030", "西柚",           "g",  "散装",      6000.0,  30000.0,  0.0180, 2),
    (31, "I031", "芒果",           "g",  "散装",      7500.0,  37500.0,  0.0250, 2),
    (32, "I032", "草莓",           "g",  "散装",      3000.0,  15000.0,  0.0380, 2),
    (33, "I033", "葡萄",           "g",  "散装",      3000.0,  15000.0,  0.0280, 2),

    # F. 果浆与风味酱 (7) -> 供应商 2 (闽南茶叶批发)
    (34, "I034", "百香果浆",       "ml", "1L/瓶",     4000.0,  15000.0,  0.0320, 2),
    (35, "I035", "蜜桃浆",         "ml", "1L/瓶",     4000.0,  15000.0,  0.0300, 2),
    (36, "I036", "芒果浆",         "ml", "1L/瓶",     5000.0,  20000.0,  0.0320, 2),
    (37, "I037", "草莓浆",         "ml", "1L/瓶",     4000.0,  15000.0,  0.0350, 2),
    (38, "I038", "葡萄浆",         "ml", "1L/瓶",     2000.0,   8000.0,  0.0300, 2),
    (39, "I039", "柚子浆",         "ml", "1L/瓶",     2000.0,   8000.0,  0.0320, 2),
    (40, "I040", "柠檬汁",         "ml", "1L/瓶",     2500.0,  10000.0,  0.0280, 2),

    # G. 冰淇淋与奶昔 (4) -> 供应商 1 (晨光乳业)
    (41, "I041", "冰淇淋浆",       "ml", "5L/袋",    12000.0,  50000.0,  0.0150, 1),
    (42, "I042", "脆皮甜筒",       "个", "100个/箱",   300.0,   1200.0,  0.4500, 1),
    (43, "I043", "可可粉",         "g",  "1kg/袋",     400.0,   1500.0,  0.0600, 1),
    (44, "I044", "巧克力酱",       "ml", "1kg/瓶",     600.0,   2500.0,  0.0400, 1),

    # H. 包材 (8) -> 供应商 3 (佳益包材)
    (45, "I045", "中杯（500ml）",  "个", "1000个/箱", 1000.0,   5000.0,  0.2200, 3),
    (46, "I046", "大杯（700ml）",  "个", "1000个/箱", 1000.0,   5000.0,  0.2800, 3),
    (47, "I047", "杯盖",           "个", "1000个/箱", 1500.0,   8000.0,  0.0800, 3),
    (48, "I048", "吸管",           "根", "2000根/箱", 2000.0,  10000.0,  0.0350, 3),
    (49, "I049", "封口膜",         "张", "3000张/卷", 2000.0,  10000.0,  0.0150, 3),
    (50, "I050", "打包袋",         "个", "1000个/箱", 1000.0,   5000.0,  0.1000, 3),
    (51, "I051", "圣代杯",         "个", "500个/箱",   400.0,   1500.0,  0.3000, 3),
    (52, "I052", "甜筒纸套",       "个", "1000个/箱",  400.0,   1500.0,  0.0600, 3),

    # I. 其它 (8) -> 混合供应商
    (53, "I053", "冰块",           "g",  "自制",      5000.0,  20000.0,  0.0010, 1),
    (54, "I054", "纯净水",         "ml", "桶装",     50000.0, 200000.0,  0.0015, 1),
    (55, "I055", "椰浆",           "ml", "1L/罐",     1000.0,   4000.0,  0.0280, 1),
    (56, "I056", "桂花酱",         "g",  "500g/罐",    400.0,   1500.0,  0.0500, 2),
    (57, "I057", "红丝绒粉",       "g",  "500g/袋",    200.0,    800.0,  0.0750, 2),
    (58, "I058", "奶盖粉",         "g",  "1kg/袋",     400.0,   1500.0,  0.0650, 1),
    (59, "I059", "蜂蜜柚子酱",     "g",  "1kg/罐",     500.0,   2000.0,  0.0380, 2),
    (60, "I060", "柠檬干片",       "g",  "200g/袋",    200.0,    800.0,  0.1200, 2),
]

INGREDIENT_SUPPLIER_MAP = {item[0]: item[8] for item in RAW_INGREDIENTS}

# 1.6 小料 tbl_topping (4项)
TOPPINGS = [
    {"topping_id": 1, "topping_code": "TP01", "topping_name": "珍珠", "ingredient_id": 17, "extra_price": 2.00, "qty_per_serving": 20.0, "is_active": 1},
    {"topping_id": 2, "topping_code": "TP02", "topping_name": "椰果", "ingredient_id": 18, "extra_price": 2.00, "qty_per_serving": 20.0, "is_active": 1},
    {"topping_id": 3, "topping_code": "TP03", "topping_name": "布丁", "ingredient_id": 19, "extra_price": 3.00, "qty_per_serving": 30.0, "is_active": 1},
    {"topping_id": 4, "topping_code": "TP04", "topping_name": "芋圆", "ingredient_id": 20, "extra_price": 3.00, "qty_per_serving": 30.0, "is_active": 1},
]

# 1.7 成品清单 tbl_product (30款)
# (product_id, product_code, product_name, category_id, base_price, product_status)
PRODUCTS = [
    {"product_id": 1,  "product_code": "P001", "product_name": "招牌柠檬水",   "category_id": 2, "base_price": 4.00,  "product_status": "ON_SALE"},
    {"product_id": 2,  "product_code": "P002", "product_name": "百香果茶",     "category_id": 2, "base_price": 7.00,  "product_status": "ON_SALE"},
    {"product_id": 3,  "product_code": "P003", "product_name": "蜜桃四季春",   "category_id": 2, "base_price": 8.00,  "product_status": "ON_SALE"},
    {"product_id": 4,  "product_code": "P004", "product_name": "珍珠奶茶",     "category_id": 1, "base_price": 7.00,  "product_status": "ON_SALE"},
    {"product_id": 5,  "product_code": "P005", "product_name": "红豆奶茶",     "category_id": 1, "base_price": 8.00,  "product_status": "ON_SALE"},
    {"product_id": 6,  "product_code": "P006", "product_name": "芋圆奶茶",     "category_id": 1, "base_price": 9.00,  "product_status": "ON_SALE"},
    {"product_id": 7,  "product_code": "P007", "product_name": "布丁奶茶",     "category_id": 1, "base_price": 8.00,  "product_status": "ON_SALE"},
    {"product_id": 8,  "product_code": "P008", "product_name": "椰果奶茶",     "category_id": 1, "base_price": 8.00,  "product_status": "ON_SALE"},
    {"product_id": 9,  "product_code": "P009", "product_name": "珍珠奶绿",     "category_id": 1, "base_price": 7.00,  "product_status": "ON_SALE"},
    {"product_id": 10, "product_code": "P010", "product_name": "黑糖珍珠鲜奶", "category_id": 1, "base_price": 10.00, "product_status": "ON_SALE"},
    {"product_id": 11, "product_code": "P011", "product_name": "抹茶奶绿",     "category_id": 1, "base_price": 9.00,  "product_status": "ON_SALE"},
    {"product_id": 12, "product_code": "P012", "product_name": "四季春茶",     "category_id": 3, "base_price": 4.00,  "product_status": "ON_SALE"},
    {"product_id": 13, "product_code": "P013", "product_name": "茉莉绿茶",     "category_id": 3, "base_price": 4.00,  "product_status": "ON_SALE"},
    {"product_id": 14, "product_code": "P014", "product_name": "经典红茶",     "category_id": 3, "base_price": 4.00,  "product_status": "ON_SALE"},
    {"product_id": 15, "product_code": "P015", "product_name": "乌龙茶",       "category_id": 3, "base_price": 5.00,  "product_status": "ON_SALE"},
    {"product_id": 16, "product_code": "P016", "product_name": "原味奶昔",     "category_id": 4, "base_price": 8.00,  "product_status": "ON_SALE"},
    {"product_id": 17, "product_code": "P017", "product_name": "草莓奶昔",     "category_id": 4, "base_price": 9.00,  "product_status": "ON_SALE"},
    {"product_id": 18, "product_code": "P018", "product_name": "巧克力奶昔",   "category_id": 4, "base_price": 9.00,  "product_status": "ON_SALE"},
    {"product_id": 19, "product_code": "P019", "product_name": "香草圣代",     "category_id": 4, "base_price": 6.00,  "product_status": "ON_SALE"},
    {"product_id": 20, "product_code": "P020", "product_name": "草莓圣代",     "category_id": 4, "base_price": 7.00,  "product_status": "ON_SALE"},
    {"product_id": 21, "product_code": "P021", "product_name": "脆皮甜筒",     "category_id": 4, "base_price": 5.00,  "product_status": "ON_SALE"},
    {"product_id": 22, "product_code": "P022", "product_name": "杨枝甘露",     "category_id": 2, "base_price": 10.00, "product_status": "ON_SALE"},
    {"product_id": 23, "product_code": "P023", "product_name": "满杯西柚",     "category_id": 2, "base_price": 9.00,  "product_status": "ON_SALE"},
    {"product_id": 24, "product_code": "P024", "product_name": "芒果冰沙",     "category_id": 2, "base_price": 10.00, "product_status": "ON_SALE"},
    {"product_id": 25, "product_code": "P025", "product_name": "草莓啵啵",     "category_id": 2, "base_price": 9.00,  "product_status": "ON_SALE"},
    {"product_id": 26, "product_code": "P026", "product_name": "葡萄冻冻",     "category_id": 2, "base_price": 9.00,  "product_status": "ON_SALE"},
    {"product_id": 27, "product_code": "P027", "product_name": "纯水",         "category_id": 3, "base_price": 2.00,  "product_status": "ON_SALE"},
    {"product_id": 28, "product_code": "P028", "product_name": "芋泥波波奶茶", "category_id": 5, "base_price": 11.00, "product_status": "ON_SALE"},
    {"product_id": 29, "product_code": "P029", "product_name": "桂花乌龙奶芙", "category_id": 5, "base_price": 11.00, "product_status": "ON_SALE"},
    {"product_id": 30, "product_code": "P030", "product_name": "红丝绒奶昔",   "category_id": 5, "base_price": 12.00, "product_status": "OFF_SALE"},
]

import re

# ==============================================================================
# 2. 配方展开生成 (Recipe BOM)
# ==============================================================================

def load_recipes_from_markdown(md_path: str) -> Optional[List[Dict[str, Any]]]:
    """从主数据唯一真相源 (weeks/week02/master-data.md) 解析配方表 (492 行)"""
    if not os.path.exists(md_path):
        return None

    try:
        with open(md_path, "r", encoding="utf-8") as f:
            content = f.read()

        prod_map = {p["product_code"]: p["product_id"] for p in PRODUCTS}
        prod_pattern = re.compile(r"^###\s+\d+\.\s+.*?[（\(](P\d{3})[）\)]", re.M)
        table_row_pattern = re.compile(r"^\|\s*([ML])\s*\|\s*([A-Za-z0-9_]+)\s*\|\s*I(\d{3})\b[^|]*\|\s*([0-9\.]+)\s*\|")

        recipes = []
        recipe_id = 1
        current_prod_id = None

        for line in content.splitlines():
            line_strip = line.strip()
            m_prod = prod_pattern.match(line_strip)
            if m_prod:
                current_code = m_prod.group(1)
                current_prod_id = prod_map.get(current_code)
                continue

            if current_prod_id:
                m_row = table_row_pattern.match(line_strip)
                if m_row:
                    cup_code, sugar_code, ing_num_str, qty_str = m_row.groups()
                    cup_id = SPEC_MAP[("CUP", cup_code)]
                    sugar_id = None if sugar_code == "ANY" else SPEC_MAP.get(("SUGAR", sugar_code))
                    ing_id = int(ing_num_str)
                    qty = round(float(qty_str), 3)

                    recipes.append({
                        "recipe_id": recipe_id,
                        "product_id": current_prod_id,
                        "cup_spec_id": cup_id,
                        "sugar_spec_id": sugar_id,
                        "ingredient_id": ing_id,
                        "qty": qty
                    })
                    recipe_id += 1

        if len(recipes) >= 400:
            return recipes
    except Exception as e:
        print(f"[WARN] 解析主数据 Markdown 配方失败 ({e})，将回退至内置配方逻辑。")

    return None

def build_all_recipes() -> List[Dict[str, Any]]:
    """生成 30 款成品的完整配方行 (优先从主数据 master-data.md 读取)"""
    # 尝试从唯一真相源 weeks/week02/master-data.md 解析
    script_dir = os.path.dirname(os.path.abspath(__file__))
    md_path = os.path.normpath(os.path.join(script_dir, "..", "..", "weeks", "week02", "master-data.md"))
    parsed_recipes = load_recipes_from_markdown(md_path)
    if parsed_recipes:
        return parsed_recipes

    # 若未找到真相源文件，则回退到内置高保真规则
    recipes = []
    recipe_id = 1

    def add_row(prod_id: int, cup_code: str, sugar_code: Optional[str], ing_id: int, qty: float):
        nonlocal recipe_id
        cup_id = SPEC_MAP[("CUP", cup_code)]
        sugar_id = SPEC_MAP[("SUGAR", sugar_code)] if sugar_code else None
        recipes.append({
            "recipe_id": recipe_id,
            "product_id": prod_id,
            "cup_spec_id": cup_id,
            "sugar_spec_id": sugar_id,
            "ingredient_id": ing_id,
            "qty": round(qty, 3)
        })
        recipe_id += 1

    def add_sugar_rows(prod_id: int, cup_code: str, sugar_ing_id: int, s30: float, s50: float, s70: float, full: float):
        add_row(prod_id, cup_code, "S30",  sugar_ing_id, s30)
        add_row(prod_id, cup_code, "S50",  sugar_ing_id, s50)
        add_row(prod_id, cup_code, "S70",  sugar_ing_id, s70)
        add_row(prod_id, cup_code, "FULL", sugar_ing_id, full)

    # 1. P001 招牌柠檬水
    for cup, pure_w, lemon_j, lemon_f, cup_ing, s_vals in [
        ("M", 350, 20, 20, 45, (15, 25, 35, 45)),
        ("L", 500, 28, 28, 46, (21, 35, 49, 63))
    ]:
        add_row(1, cup, None, 54, pure_w)
        add_row(1, cup, None, 40, lemon_j)
        add_row(1, cup, None, 27, lemon_f)
        add_row(1, cup, None, cup_ing, 1)
        add_row(1, cup, None, 48, 1) # 吸管
        add_sugar_rows(1, cup, 12, *s_vals)

    # 2. P004 珍珠奶茶
    for cup, tea, creamer, pearl, cup_ing, s_vals in [
        ("M", 5, 15, 20, 45, (10, 15, 20, 25)),
        ("L", 7, 21, 28, 46, (14, 21, 28, 35))
    ]:
        add_row(4, cup, None, 1, tea)
        add_row(4, cup, None, 7, creamer)
        add_row(4, cup, None, 17, pearl)
        add_row(4, cup, None, cup_ing, 1)
        add_row(4, cup, None, 48, 1)
        add_sugar_rows(4, cup, 12, *s_vals)

    # 3. P002 百香果茶
    for cup, tea, pulp, fruit, cup_ing, s_vals in [
        ("M", 4, 40, 25, 45, (12, 20, 28, 36)),
        ("L", 6, 56, 35, 46, (17, 28, 39, 50))
    ]:
        add_row(2, cup, None, 3, tea)
        add_row(2, cup, None, 34, pulp)
        add_row(2, cup, None, 28, fruit)
        add_row(2, cup, None, cup_ing, 1)
        add_row(2, cup, None, 48, 1)
        add_sugar_rows(2, cup, 12, *s_vals)

    # 4. P003 蜜桃四季春
    for cup, tea, pulp, fruit, cup_ing, s_vals in [
        ("M", 5, 35, 40, 45, (10, 17, 24, 31)),
        ("L", 7, 49, 56, 46, (14, 24, 34, 43))
    ]:
        add_row(3, cup, None, 3, tea)
        add_row(3, cup, None, 35, pulp)
        add_row(3, cup, None, 29, fruit)
        add_row(3, cup, None, cup_ing, 1)
        add_row(3, cup, None, 48, 1)
        add_sugar_rows(3, cup, 12, *s_vals)

    # 5. P010 黑糖珍珠鲜奶
    for cup, milk, brown_s, pearl, cup_ing, s_vals in [
        ("M", 250, 30, 25, 45, (5, 10, 15, 20)),
        ("L", 350, 42, 35, 46, (7, 14, 21, 28))
    ]:
        add_row(10, cup, None, 8, milk)
        add_row(10, cup, None, 14, brown_s)
        add_row(10, cup, None, 17, pearl)
        add_row(10, cup, None, cup_ing, 1)
        add_row(10, cup, None, 48, 1)
        add_sugar_rows(10, cup, 13, *s_vals) # 蔗糖浆

    # 6. P019 香草圣代 (仅 M，无糖度选项)
    add_row(19, "M", None, 41, 120) # 冰淇淋浆
    add_row(19, "M", None, 16, 10)  # 香草糖浆
    add_row(19, "M", None, 51, 1)   # 圣代杯

    # 7. P012 四季春茶
    for cup, tea, water, cup_ing, s_vals in [
        ("M", 6, 400, 45, (12, 20, 28, 36)),
        ("L", 8, 550, 46, (17, 28, 39, 50))
    ]:
        add_row(12, cup, None, 3, tea)
        add_row(12, cup, None, 54, water)
        add_row(12, cup, None, cup_ing, 1)
        add_row(12, cup, None, 48, 1)
        add_sugar_rows(12, cup, 12, *s_vals)

    # 8. P016 原味奶昔
    for cup, ice_mix, milk, cup_ing, s_vals in [
        ("M", 120, 100, 45, (8, 14, 20, 26)),
        ("L", 170, 140, 46, (11, 20, 28, 36))
    ]:
        add_row(16, cup, None, 41, ice_mix)
        add_row(16, cup, None, 8, milk)
        add_row(16, cup, None, cup_ing, 1)
        add_row(16, cup, None, 48, 1)
        add_sugar_rows(16, cup, 12, *s_vals)

    # 9. P022 杨枝甘露
    for cup, tea, mango_p, mango_f, gf, coconut, sago, cup_ing, s_vals in [
        ("M", 4, 50, 60, 30, 40, 20, 45, (8, 14, 20, 26)),
        ("L", 6, 70, 84, 42, 56, 28, 46, (11, 20, 28, 36))
    ]:
        add_row(22, cup, None, 3, tea)
        add_row(22, cup, None, 36, mango_p)
        add_row(22, cup, None, 31, mango_f)
        add_row(22, cup, None, 30, gf)
        add_row(22, cup, None, 55, coconut)
        add_row(22, cup, None, 21, sago)
        add_row(22, cup, None, cup_ing, 1)
        add_row(22, cup, None, 48, 1)
        add_sugar_rows(22, cup, 12, *s_vals)

    # 10. P021 脆皮甜筒 (仅 M，无糖度)
    add_row(21, "M", None, 41, 90) # 冰淇淋浆
    add_row(21, "M", None, 42, 1)  # 脆皮甜筒
    add_row(21, "M", None, 52, 1)  # 甜筒纸套

    # 其余 20 款成品的配方标准配置
    # P005 红豆奶茶 (红茶+植脂末+蜜红豆)
    # P006 芋圆奶茶 (红茶+植脂末+芋圆)
    # P007 布丁奶茶 (红茶+植脂末+布丁粉)
    # P008 椰果奶茶 (红茶+植脂末+椰果)
    topping_teas = [(5, 22), (6, 20), (7, 19), (8, 18)]
    for pid, top_ing in topping_teas:
        for cup, cup_ing, s_vals in [("M", 45, (10, 15, 20, 25)), ("L", 46, (14, 21, 28, 35))]:
            add_row(pid, cup, None, 1, 5 if cup=="M" else 7)
            add_row(pid, cup, None, 7, 15 if cup=="M" else 21)
            add_row(pid, cup, None, top_ing, 20 if cup=="M" else 28)
            add_row(pid, cup, None, cup_ing, 1)
            add_row(pid, cup, None, 48, 1)
            add_sugar_rows(pid, cup, 12, *s_vals)

    # P009 珍珠奶绿 (茉莉绿茶+植脂末+珍珠)
    for cup, cup_ing, s_vals in [("M", 45, (10, 15, 20, 25)), ("L", 46, (14, 21, 28, 35))]:
        add_row(9, cup, None, 2, 5 if cup=="M" else 7)
        add_row(9, cup, None, 7, 15 if cup=="M" else 21)
        add_row(9, cup, None, 17, 20 if cup=="M" else 28)
        add_row(9, cup, None, cup_ing, 1)
        add_row(9, cup, None, 48, 1)
        add_sugar_rows(9, cup, 12, *s_vals)

    # P011 抹茶奶绿 (抹茶粉+纯牛奶)
    for cup, cup_ing, s_vals in [("M", 45, (10, 15, 20, 25)), ("L", 46, (14, 21, 28, 35))]:
        add_row(11, cup, None, 6, 8 if cup=="M" else 12)
        add_row(11, cup, None, 8, 180 if cup=="M" else 250)
        add_row(11, cup, None, cup_ing, 1)
        add_row(11, cup, None, 48, 1)
        add_sugar_rows(11, cup, 12, *s_vals)

    # P013 茉莉绿茶, P014 经典红茶, P015 乌龙茶
    pure_teas = [(13, 2), (14, 1), (15, 4)]
    for pid, tea_ing in pure_teas:
        for cup, cup_ing, s_vals in [("M", 45, (12, 20, 28, 36)), ("L", 46, (17, 28, 39, 50))]:
            add_row(pid, cup, None, tea_ing, 6 if cup=="M" else 8)
            add_row(pid, cup, None, 54, 400 if cup=="M" else 550)
            add_row(pid, cup, None, cup_ing, 1)
            add_row(pid, cup, None, 48, 1)
            add_sugar_rows(pid, cup, 12, *s_vals)

    # P017 草莓奶昔 (冰淇淋+牛奶+草莓浆)
    for cup, cup_ing, s_vals in [("M", 45, (8, 14, 20, 26)), ("L", 46, (11, 20, 28, 36))]:
        add_row(17, cup, None, 41, 120 if cup=="M" else 170)
        add_row(17, cup, None, 8, 80 if cup=="M" else 110)
        add_row(17, cup, None, 37, 30 if cup=="M" else 40)
        add_row(17, cup, None, cup_ing, 1)
        add_row(17, cup, None, 48, 1)
        add_sugar_rows(17, cup, 12, *s_vals)

    # P018 巧克力奶昔 (冰淇淋+牛奶+巧克力酱+可可粉)
    for cup, cup_ing, s_vals in [("M", 45, (8, 14, 20, 26)), ("L", 46, (11, 20, 28, 36))]:
        add_row(18, cup, None, 41, 120 if cup=="M" else 170)
        add_row(18, cup, None, 8, 80 if cup=="M" else 110)
        add_row(18, cup, None, 44, 25 if cup=="M" else 35)
        add_row(18, cup, None, 43, 5 if cup=="M" else 8)
        add_row(18, cup, None, cup_ing, 1)
        add_row(18, cup, None, 48, 1)
        add_sugar_rows(18, cup, 12, *s_vals)

    # P020 草莓圣代 (仅 M，无糖度)
    add_row(20, "M", None, 41, 120)
    add_row(20, "M", None, 37, 20)
    add_row(20, "M", None, 32, 20) # 鲜草莓
    add_row(20, "M", None, 51, 1)

    # P023 满杯西柚 (四季春+西柚+柚子浆+水)
    for cup, cup_ing, s_vals in [("M", 45, (10, 18, 26, 34)), ("L", 46, (14, 25, 36, 48))]:
        add_row(23, cup, None, 3, 5 if cup=="M" else 7)
        add_row(23, cup, None, 30, 80 if cup=="M" else 110)
        add_row(23, cup, None, 39, 30 if cup=="M" else 40)
        add_row(23, cup, None, 54, 250 if cup=="M" else 350)
        add_row(23, cup, None, cup_ing, 1)
        add_row(23, cup, None, 48, 1)
        add_sugar_rows(23, cup, 12, *s_vals)

    # P024 芒果冰沙 (芒果+芒果浆+纯水)
    for cup, cup_ing, s_vals in [("M", 45, (8, 15, 22, 30)), ("L", 46, (12, 21, 30, 42))]:
        add_row(24, cup, None, 31, 100 if cup=="M" else 140)
        add_row(24, cup, None, 36, 40 if cup=="M" else 55)
        add_row(24, cup, None, 54, 200 if cup=="M" else 280)
        add_row(24, cup, None, cup_ing, 1)
        add_row(24, cup, None, 48, 1)
        add_sugar_rows(24, cup, 12, *s_vals)

    # P025 草莓啵啵 (绿茶+草莓+草莓浆+啵啵脆)
    for cup, cup_ing, s_vals in [("M", 45, (10, 18, 25, 32)), ("L", 46, (14, 25, 35, 45))]:
        add_row(25, cup, None, 2, 4 if cup=="M" else 6)
        add_row(25, cup, None, 32, 60 if cup=="M" else 80)
        add_row(25, cup, None, 37, 30 if cup=="M" else 40)
        add_row(25, cup, None, 24, 20 if cup=="M" else 28)
        add_row(25, cup, None, cup_ing, 1)
        add_row(25, cup, None, 48, 1)
        add_sugar_rows(25, cup, 12, *s_vals)

    # P026 葡萄冻冻 (绿茶+葡萄+葡萄浆+仙草冻)
    for cup, cup_ing, s_vals in [("M", 45, (10, 18, 25, 32)), ("L", 46, (14, 25, 35, 45))]:
        add_row(26, cup, None, 2, 4 if cup=="M" else 6)
        add_row(26, cup, None, 33, 60 if cup=="M" else 80)
        add_row(26, cup, None, 38, 30 if cup=="M" else 40)
        add_row(26, cup, None, 23, 20 if cup=="M" else 28)
        add_row(26, cup, None, cup_ing, 1)
        add_row(26, cup, None, 48, 1)
        add_sugar_rows(26, cup, 12, *s_vals)

    # P027 纯水 (极简边界样本: 水+杯+吸管)
    for cup, cup_ing in [("M", 45), ("L", 46)]:
        add_row(27, cup, None, 54, 400 if cup=="M" else 550)
        add_row(27, cup, None, cup_ing, 1)
        add_row(27, cup, None, 48, 1)

    # P028 芋泥波波奶茶 (红茶+牛奶+芋泥+啵啵脆)
    for cup, cup_ing, s_vals in [("M", 45, (8, 14, 20, 26)), ("L", 46, (11, 20, 28, 36))]:
        add_row(28, cup, None, 1, 5 if cup=="M" else 7)
        add_row(28, cup, None, 8, 150 if cup=="M" else 200)
        add_row(28, cup, None, 25, 40 if cup=="M" else 55)
        add_row(28, cup, None, 24, 20 if cup=="M" else 28)
        add_row(28, cup, None, cup_ing, 1)
        add_row(28, cup, None, 48, 1)
        add_sugar_rows(28, cup, 13, *s_vals)

    # P029 桂花乌龙奶芙 (乌龙+牛奶+淡奶油+桂花酱+奶盖粉)
    for cup, cup_ing, s_vals in [("M", 45, (8, 14, 20, 26)), ("L", 46, (11, 20, 28, 36))]:
        add_row(29, cup, None, 4, 5 if cup=="M" else 7)
        add_row(29, cup, None, 8, 150 if cup=="M" else 200)
        add_row(29, cup, None, 9, 30 if cup=="M" else 40)
        add_row(29, cup, None, 56, 15 if cup=="M" else 20)
        add_row(29, cup, None, 58, 10 if cup=="M" else 15)
        add_row(29, cup, None, cup_ing, 1)
        add_row(29, cup, None, 48, 1)
        add_sugar_rows(29, cup, 12, *s_vals)

    # P030 红丝绒奶昔 (停售，配方完整留存)
    for cup, cup_ing, s_vals in [("M", 45, (8, 14, 20, 26)), ("L", 46, (11, 20, 28, 36))]:
        add_row(30, cup, None, 41, 120 if cup=="M" else 170)
        add_row(30, cup, None, 8, 80 if cup=="M" else 110)
        add_row(30, cup, None, 57, 10 if cup=="M" else 15)
        add_row(30, cup, None, cup_ing, 1)
        add_row(30, cup, None, 48, 1)
        add_sugar_rows(30, cup, 12, *s_vals)

    return recipes

RECIPES = build_all_recipes()

# 建立快速索引: (product_id, cup_spec_id) -> 基础配方行 (sugar_spec_id is None)
#              (product_id, cup_spec_id, sugar_spec_id) -> 糖配方行
RECIPE_BASE_INDEX: Dict[Tuple[int, int], List[Dict[str, Any]]] = {}
RECIPE_SUGAR_INDEX: Dict[Tuple[int, int, int], Dict[str, Any]] = {}

for r in RECIPES:
    pid = r["product_id"]
    cid = r["cup_spec_id"]
    sid = r["sugar_spec_id"]
    if sid is None:
        RECIPE_BASE_INDEX.setdefault((pid, cid), []).append(r)
    else:
        RECIPE_SUGAR_INDEX[(pid, cid, sid)] = r

# ==============================================================================
# 3. 内存仿真模型与状态流转
# ==============================================================================

class ShopSimulation:
    def __init__(self, days: int = 7, start_date_str: str = "2026-09-17", seed: int = DEFAULT_SEED, enable_variance: bool = False):
        self.days = days
        self.start_date = datetime.strptime(start_date_str, "%Y-%m-%d").date()
        self.seed = seed
        self.enable_variance = enable_variance

        random.seed(self.seed)

        # 17 张核心表内存存储
        self.tbl_employee = [dict(e) for e in EMPLOYEES]
        self.tbl_product_category = [dict(c) for c in CATEGORIES]
        self.tbl_supplier = [dict(s) for s in SUPPLIERS]
        self.tbl_spec_option = [dict(o) for o in SPEC_OPTIONS]
        self.tbl_product = [dict(p) for p in PRODUCTS]
        self.tbl_topping = [dict(t) for t in TOPPINGS]
        self.tbl_recipe = RECIPES

        # 原料表与实时库存
        self.tbl_ingredient = []
        self.current_stock: Dict[int, float] = {}
        self.moving_avg_cost: Dict[int, float] = {}
        self.is_sold_out: Dict[int, int] = {}
        self.init_opening_balance: Dict[int, float] = {}

        for item in RAW_INGREDIENTS:
            ing_id, code, name, unit, spec, reorder, target, cost, sup_id = item
            # 初始建账库存设为目标水位的大约 80%~95%
            init_qty = round(target * 0.85, 3)
            self.tbl_ingredient.append({
                "ingredient_id": ing_id,
                "ingredient_code": code,
                "ingredient_name": name,
                "unit": unit,
                "spec": spec,
                "qty_on_hand": init_qty,
                "reorder_point": reorder,
                "target_level": target,
                "moving_avg_cost": cost,
                "is_sold_out": 0,
                "is_active": 1
            })
            self.current_stock[ing_id] = init_qty
            self.moving_avg_cost[ing_id] = cost
            self.is_sold_out[ing_id] = 0
            self.init_opening_balance[ing_id] = init_qty

        # 动态业务表
        self.tbl_member: List[Dict[str, Any]] = []
        self.tbl_coupon: List[Dict[str, Any]] = []
        self.tbl_order_header: List[Dict[str, Any]] = []
        self.tbl_order_detail: List[Dict[str, Any]] = []
        self.tbl_order_detail_topping: List[Dict[str, Any]] = []
        self.tbl_stock_ledger: List[Dict[str, Any]] = []
        self.tbl_points_ledger: List[Dict[str, Any]] = []
        self.tbl_purchase_order: List[Dict[str, Any]] = []
        self.tbl_purchase_order_detail: List[Dict[str, Any]] = []

        # 自增主键计数器
        self.next_member_id = 1
        self.next_coupon_id = 1
        self.next_order_id = 1
        self.next_order_detail_id = 1
        self.next_od_topping_id = 1
        self.next_ledger_id = 1001
        self.next_point_ledger_id = 1
        self.next_po_id = 1
        self.next_po_detail_id = 1

        # 会员资金/积分管理
        self.member_points: Dict[int, int] = {}

        # 待到货采购单队列: arrival_date -> list of po_id
        self.pending_deliveries: Dict[date, List[int]] = {}

        # 进销存累计流水审计 (用于期末自洽断言)
        self.total_purchase_in: Dict[int, float] = {ing_id: 0.0 for ing_id in self.current_stock}
        self.total_sales_use: Dict[int, float] = {ing_id: 0.0 for ing_id in self.current_stock}
        self.total_loss: Dict[int, float] = {ing_id: 0.0 for ing_id in self.current_stock}

    def init_simulation(self):
        """初始化会员池与期初结转库存流水"""
        # 1. 初始化 80 名会员 (刘洋、周婷、吴磊领衔)
        vip_names = ["刘洋", "周婷", "吴磊", "张强", "李思思", "王俊", "赵若曦", "钱宇", "孙茜", "周博"]
        surnames = ["王", "李", "张", "刘", "陈", "杨", "赵", "黄", "周", "吴", "徐", "孙", "胡", "朱", "高"]
        givennames = ["伟", "芳", "娜", "敏", "静", "丽", "强", "磊", "洋", "艳", "勇", "军", "杰", "娟", "涛", "明", "超", "秀英", "霞", "平"]

        for i in range(1, 81):
            name = vip_names[i-1] if i <= len(vip_names) else f"{random.choice(surnames)}{random.choice(givennames)}"
            phone = f"138{i:08d}"
            # 会员注册时间在营业日前 30~90 天
            reg_date = (self.start_date - timedelta(days=random.randint(15, 90))).strftime("%Y-%m-%d")
            init_pts = random.randint(20, 200) if i > 3 else (320 if i == 1 else (94 if i == 2 else 1240))
            
            member = {
                "member_id": self.next_member_id,
                "member_code": f"M{i:03d}",
                "member_phone": phone,
                "member_name": name,
                "register_date": reg_date,
                "points_balance": init_pts
            }
            self.tbl_member.append(member)
            self.member_points[self.next_member_id] = init_pts
            self.next_member_id += 1

        # 2. 初始预发部分优惠券 (活动赠与 或 积分兑换)
        for i in range(1, 25):
            mid = random.randint(1, 40)
            valid_start = self.start_date - timedelta(days=5)
            valid_end = valid_start + timedelta(days=30)
            coupon = {
                "coupon_id": self.next_coupon_id,
                "coupon_code": f"CP{valid_start.strftime('%Y%m%d')}{i:03d}",
                "member_id": mid,
                "coupon_name": "5元无门槛券",
                "source": "CAMPAIGN" if i % 2 == 0 else "POINTS_EXCHANGE",
                "discount_amount": 5.00,
                "min_order_amount": 0.00,
                "valid_from": f"{valid_start} 00:00:00",
                "valid_to": f"{valid_end} 23:59:59",
                "status": "UNUSED",
                "used_time": None
            }
            self.tbl_coupon.append(coupon)
            self.next_coupon_id += 1

        # 3. 生成 Day 1 08:00:00 的期初结转库存流水 (OPENING)
        # 符合 DOM-04 ('PURCHASE_IN') 和 DOM-05 ('OPENING')
        day1_str = self.start_date.strftime("%Y-%m-%d")
        for ing_id, init_qty in self.init_opening_balance.items():
            self.tbl_stock_ledger.append({
                "ledger_id": self.next_ledger_id,
                "ingredient_id": ing_id,
                "ledger_type": "PURCHASE_IN",
                "qty": round(init_qty, 3),
                "ref_type": "OPENING",
                "purchase_order_id": None,
                "order_id": None,
                "operator_id": 5, # 库管员陈静
                "ledger_time": f"{day1_str} 08:00:00",
                "remark": "期初建账盘点录入"
            })
            self.next_ledger_id += 1

    def run(self):
        """主推进循环: 逐日推演"""
        self.init_simulation()

        current_d = self.start_date
        end_d = self.start_date + timedelta(days=self.days)

        day_idx = 1
        while current_d < end_d:
            is_weekend = (current_d.weekday() >= 5) # 5=周六, 6=周日
            is_last_day = (day_idx == self.days)
            self.simulate_day(current_d, is_weekend, is_last_day)
            current_d += timedelta(days=1)
            day_idx += 1

        # 仿真结束，同步最后原料表状态与断言
        self.finalize_ingredient_table()
        self.assert_reconciliation()

    def simulate_day(self, current_d: date, is_weekend: bool, is_last_day: bool):
        """单日推进: 到货验收 -> 客流点单 -> 打烊报损 -> 补货巡检"""
        date_str = current_d.strftime("%Y-%m-%d")

        # ----------------------------------------------------------------------
        # ① 08:30~09:30 采购到货验收 (Arrival & Receiving)
        # ----------------------------------------------------------------------
        if current_d in self.pending_deliveries:
            for po_id in self.pending_deliveries[current_d]:
                po = next(p for p in self.tbl_purchase_order if p["purchase_order_id"] == po_id)
                po["arrival_date"] = date_str
                po["received_by"] = 5 # 库管员陈静

                # 获取该采购单的所有明细
                details = [d for d in self.tbl_purchase_order_detail if d["purchase_order_id"] == po_id]
                has_partial = False

                for d in details:
                    ing_id = d["ingredient_id"]
                    ordered_qty = d["qty_ordered"]
                    unit_price = d["unit_price"]

                    # 98% 全量验收，2% 部分拒收
                    if random.random() < 0.02:
                        received_qty = round(ordered_qty * random.uniform(0.85, 0.95), 1)
                        has_partial = True
                    else:
                        received_qty = ordered_qty

                    d["qty_received"] = received_qty

                    # 写入库存流水 PURCHASE_IN
                    self.tbl_stock_ledger.append({
                        "ledger_id": self.next_ledger_id,
                        "ingredient_id": ing_id,
                        "ledger_type": "PURCHASE_IN",
                        "qty": round(received_qty, 3),
                        "ref_type": "PURCHASE",
                        "purchase_order_id": po_id,
                        "order_id": None,
                        "operator_id": 5,
                        "ledger_time": f"{date_str} 09:15:00",
                        "remark": None
                    })
                    self.next_ledger_id += 1

                    # 更新实时库存与移动加权成本
                    old_stock = self.current_stock[ing_id]
                    old_cost = self.moving_avg_cost[ing_id]
                    new_stock = old_stock + received_qty
                    if new_stock > 0:
                        new_cost = (old_stock * old_cost + received_qty * unit_price) / new_stock
                    else:
                        new_cost = old_cost

                    self.current_stock[ing_id] = round(new_stock, 3)
                    self.moving_avg_cost[ing_id] = round(new_cost, 4)
                    self.total_purchase_in[ing_id] += received_qty

                    # 若此前沽清且库存已达安全水位，自动复位沽清状态
                    if self.is_sold_out[ing_id] == 1 and not (is_last_day and ing_id == 31):
                        self.is_sold_out[ing_id] = 0

                po["order_status"] = "PARTIAL" if has_partial else "ACCEPTED"

        # ----------------------------------------------------------------------
        # ② 10:00~22:00 营业客流与点单消费 (Poisson & Peak Hours)
        # ----------------------------------------------------------------------
        # 平日 200~280 单 (均值 240)，周末 320~380 单 (均值 350)
        daily_order_count = int(random.normalvariate(350, 15) if is_weekend else random.normalvariate(240, 12))
        daily_order_count = max(180, min(daily_order_count, 420))

        # 模拟特定日期的高峰原料沽清测试
        # 在第 7 天下午将 I031 (芒果) 设为沽清，保留至期末供第 4 周写售罄视图做真实查询证据！
        if is_last_day:
            self.is_sold_out[31] = 1 # 芒果沽清

        # 生成全天订单时间戳分布
        order_times = self.generate_daily_timestamps(current_d, daily_order_count)

        for pickup_no, o_time in enumerate(order_times, start=1):
            self.simulate_single_order(current_d, date_str, pickup_no, o_time)

        # ----------------------------------------------------------------------
        # ③ 22:00~22:30 闭店打烊报损 (Daily Closing LOSS)
        # ----------------------------------------------------------------------
        # 每日对易耗散装物料进行合理打烊清盘报损 (红茶折干重、鲜果、珍珠等)
        loss_candidates = [
            (1,  "红茶（阿萨姆）", 15.0, 35.0, "打烊清盘：茶汤弃置折干重"),
            (2,  "茉莉绿茶",       15.0, 30.0, "打烊清盘：茶汤弃置折干重"),
            (17, "珍珠（生）",     40.0, 90.0, "打烊清盘：熟珍珠报损折干重"),
            (27, "柠檬",           50.0, 150.0, "打烊清盘：柠檬切片风干报损"),
            (28, "百香果",         30.0, 80.0,  "打烊清盘：鲜果挖肉损耗"),
            (29, "蜜桃",           40.0, 100.0, "打烊清盘：切块鲜果氧化损耗"),
            (31, "芒果",           50.0, 120.0, "打烊清盘：切丁鲜果残损"),
        ]

        maker_id = random.choice([3, 4]) # 王强 或 赵敏
        for ing_id, ing_name, min_l, max_l, reason in loss_candidates:
            # 确保库存充足才扣除报损
            loss_qty = round(random.uniform(min_l, max_l), 1)
            if self.current_stock[ing_id] >= loss_qty + 10.0:
                self.current_stock[ing_id] = round(self.current_stock[ing_id] - loss_qty, 3)
                self.total_loss[ing_id] += loss_qty

                self.tbl_stock_ledger.append({
                    "ledger_id": self.next_ledger_id,
                    "ingredient_id": ing_id,
                    "ledger_type": "LOSS",
                    "qty": -loss_qty,
                    "ref_type": "MANUAL",
                    "purchase_order_id": None,
                    "order_id": None,
                    "operator_id": maker_id,
                    "ledger_time": f"{date_str} 22:15:00",
                    "remark": reason
                })
                self.next_ledger_id += 1

        # ----------------------------------------------------------------------
        # ④ 22:30 夜间库存巡检与自动触发补货采购 (Automated Reordering)
        # ----------------------------------------------------------------------
        # 遍历所有原料，检查低于补货点的物料，合并按供应商生成采购单
        needed_by_supplier: Dict[int, List[Tuple[int, float, float]]] = {}

        for ing in self.tbl_ingredient:
            ing_id = ing["ingredient_id"]
            curr = self.current_stock[ing_id]
            reorder = ing["reorder_point"]
            target = ing["target_level"]

            if curr < reorder:
                # 订购量 = 补至目标水位
                order_qty = round(target - curr, 1)
                sup_id = INGREDIENT_SUPPLIER_MAP.get(ing_id, 1)
                cost = self.moving_avg_cost[ing_id]
                needed_by_supplier.setdefault(sup_id, []).append((ing_id, order_qty, cost))

        # 为每个有缺料的供应商生成采购单
        tomorrow = current_d + timedelta(days=1)
        for sup_id, items in needed_by_supplier.items():
            po_id = self.next_po_id
            self.next_po_id += 1
            po_no = f"PO{current_d.strftime('%Y%m%d')}{po_id:03d}"

            self.tbl_purchase_order.append({
                "purchase_order_id": po_id,
                "purchase_no": po_no,
                "supplier_id": sup_id,
                "order_date": date_str,
                "arrival_date": None,       # 次日入库前为 NULL
                "order_status": "ORDERED",
                "ordered_by": 1,            # 店长张伟
                "received_by": None         # 验收前为 NULL
            })

            for ing_id, o_qty, cost in items:
                self.tbl_purchase_order_detail.append({
                    "purchase_order_detail_id": self.next_po_detail_id,
                    "purchase_order_id": po_id,
                    "ingredient_id": ing_id,
                    "qty_ordered": o_qty,
                    "qty_received": 0.0,
                    "unit_price": cost
                })
                self.next_po_detail_id += 1

            # 注册次日早晨到货
            self.pending_deliveries.setdefault(tomorrow, []).append(po_id)

    def generate_daily_timestamps(self, current_d: date, count: int) -> List[datetime]:
        """按真实营业时间 (10:00~22:00) 双峰分布生成订单时间戳"""
        # 午高峰 12:00~13:30 (权重 30%), 下午茶 14:30~16:00 (权重 35%), 晚高峰 18:00~20:00 (权重 20%), 其余平缓 (15%)
        times = []
        for _ in range(count):
            p = random.random()
            if p < 0.30: # 午高峰 (11:30 ~ 13:30)
                minute_offset = random.randint(11 * 60 + 30, 13 * 60 + 30)
            elif p < 0.65: # 下午茶 (14:00 ~ 16:30)
                minute_offset = random.randint(14 * 60, 16 * 60 + 30)
            elif p < 0.85: # 晚高峰 (17:30 ~ 20:00)
                minute_offset = random.randint(17 * 60 + 30, 20 * 60)
            else: # 其余时段 (10:00~11:30 或 20:00~21:55)
                if random.random() < 0.5:
                    minute_offset = random.randint(10 * 60, 11 * 60 + 30)
                else:
                    minute_offset = random.randint(20 * 60, 21 * 60 + 55)

            sec = random.randint(0, 59)
            dt = datetime(current_d.year, current_d.month, current_d.day, minute_offset // 60, minute_offset % 60, sec)
            times.append(dt)

        times.sort()
        return times

    def can_fulfill_item(self, pid: int, cup_id: int, sugar_id: Optional[int], toppings: List[Tuple[Any, int, float]], qty: int = 1) -> bool:
        """检查单项饮品所需原料是否充沛，若原料不足则自动触发该原料沽清并拒绝本单品"""
        # 1. 检查基础配方
        for r in RECIPE_BASE_INDEX.get((pid, cup_id), []):
            ing_id = r["ingredient_id"]
            needed = float(r["qty"]) * qty
            if self.current_stock[ing_id] < needed:
                self.is_sold_out[ing_id] = 1
                return False

        # 2. 检查糖度配方
        if sugar_id is not None:
            sugar_r = RECIPE_SUGAR_INDEX.get((pid, cup_id, sugar_id))
            if sugar_r:
                ing_id = sugar_r["ingredient_id"]
                needed = float(sugar_r["qty"]) * qty
                if self.current_stock[ing_id] < needed:
                    self.is_sold_out[ing_id] = 1
                    return False

        # 3. 检查小料
        for top, top_qty, _ in toppings:
            ing_id = top["ingredient_id"]
            needed = float(top["qty_per_serving"]) * top_qty * qty
            if self.current_stock[ing_id] < needed:
                self.is_sold_out[ing_id] = 1
                return False

        return True

    def simulate_single_order(self, current_d: date, date_str: str, pickup_no: int, o_time: datetime):
        """生成单笔订单并严格执行反冲扣料"""
        order_id = self.next_order_id
        self.next_order_id += 1
        order_no = f"{current_d.strftime('%Y%m%d')}-{pickup_no:04d}"

        # 1. 会员识别 (60% 概率为会员)
        is_member = (random.random() < 0.60)
        member_id = random.randint(1, len(self.tbl_member)) if is_member else None

        # 2. 挑选 1~3 款明细成品
        item_count = random.choices([1, 2, 3], weights=[0.70, 0.25, 0.05])[0]
        line_items: List[Dict[str, Any]] = []

        # 过滤在售商品 (P030 停售；若原料沽清则过滤含该原料的成品)
        def get_available_products():
            return [
                p for p in self.tbl_product 
                if p["product_status"] == "ON_SALE" and not (self.is_sold_out[31] and p["product_id"] in (22, 24))
            ]

        for line_no in range(1, item_count + 1):
            chosen_item = None
            available_products = get_available_products()

            # 尝试最多 6 次挑选库存充沛的商品
            for _ in range(6):
                product = random.choice(available_products)
                pid = product["product_id"]
                base_p = float(product["base_price"])

                # 规格选项决策
                if pid in (19, 20, 21):
                    cup_id = SPEC_MAP[("CUP", "M")]
                    sugar_id = None
                    ice_id = None
                    extra_cup_p = 0.00
                elif pid == 27: # 纯水
                    cup_code = "M" if random.random() < 0.6 else "L"
                    cup_id = SPEC_MAP[("CUP", cup_code)]
                    sugar_id = None
                    ice_id = SPEC_MAP[("ICE", random.choice(["NO_ICE", "NORMAL"]))]
                    extra_cup_p = 3.00 if cup_code == "L" else 0.00
                else:
                    cup_code = "M" if random.random() < 0.55 else "L"
                    cup_id = SPEC_MAP[("CUP", cup_code)]
                    extra_cup_p = 3.00 if cup_code == "L" else 0.00

                    # 糖度分布
                    sugar_code = random.choices(
                        ["NONE", "S30", "S50", "S70", "FULL"],
                        weights=[0.10, 0.25, 0.40, 0.15, 0.10]
                    )[0]
                    sugar_id = SPEC_MAP[("SUGAR", sugar_code)]

                    # 冰量分布
                    ice_code = random.choices(
                        ["NO_ICE", "LESS", "NORMAL", "HOT"],
                        weights=[0.10, 0.35, 0.45, 0.10]
                    )[0]
                    ice_id = SPEC_MAP[("ICE", ice_code)]

                unit_price = base_p + extra_cup_p
                qty = 1

                # 可选加料
                toppings_chosen = []
                topping_subtotal = 0.00
                if pid not in (19, 20, 21, 27) and random.random() < 0.25:
                    top = random.choice(TOPPINGS)
                    top_qty = 1
                    top_extra = float(top["extra_price"])
                    toppings_chosen.append((top, top_qty, top_extra))
                    topping_subtotal += top_extra * top_qty

                # 原料充足性预检
                if self.can_fulfill_item(pid, cup_id, sugar_id, toppings_chosen, qty):
                    subtotal = unit_price * qty + topping_subtotal
                    chosen_item = {
                        "line_no": line_no,
                        "product_id": pid,
                        "qty": qty,
                        "unit_price": unit_price,
                        "cup_spec_id": cup_id,
                        "sugar_spec_id": sugar_id,
                        "ice_spec_id": ice_id,
                        "subtotal": subtotal,
                        "toppings": toppings_chosen
                    }
                    break

            # 若多次未挑中，回退至纯茶 P012 (四季春茶) 或纯水 P027
            if not chosen_item:
                fallback_pid = 12 if self.current_stock[3] > 10 else 27
                fallback_base = 4.00 if fallback_pid == 12 else 2.00
                cid = SPEC_MAP[("CUP", "M")]
                sid = SPEC_MAP[("SUGAR", "NONE")] if fallback_pid == 12 else None
                iid = SPEC_MAP[("ICE", "NORMAL")] if fallback_pid == 12 else None
                chosen_item = {
                    "line_no": line_no,
                    "product_id": fallback_pid,
                    "qty": 1,
                    "unit_price": fallback_base,
                    "cup_spec_id": cid,
                    "sugar_spec_id": sid,
                    "ice_spec_id": iid,
                    "subtotal": fallback_base,
                    "toppings": []
                }

            line_items.append(chosen_item)

        items_total = sum(item["subtotal"] for item in line_items)

        # 3. 优惠券使用判定
        coupon_id = None
        discount_amount = 0.00
        if member_id and items_total >= 10.0:
            # 查找该会员是否有未使用的有效券
            unused_coupon = next(
                (c for c in self.tbl_coupon if c["member_id"] == member_id and c["status"] == "UNUSED"),
                None
            )
            if unused_coupon:
                coupon_id = unused_coupon["coupon_id"]
                discount_amount = min(items_total, float(unused_coupon["discount_amount"]))
                unused_coupon["status"] = "USED"
                unused_coupon["used_time"] = o_time.strftime("%Y-%m-%d %H:%M:%S")

        amount_due = max(0.00, items_total - discount_amount)
        amount_paid = amount_due

        # 4. 订单状态与支付信息
        # 96% COMPLETED, 2% CANCELLED, 2% ABANDONED
        st_roll = random.random()
        if st_roll < 0.96:
            order_status = "COMPLETED"
            pay_status = "SUCCESS"
            finish_time_str = (o_time + timedelta(minutes=random.randint(3, 8))).strftime("%Y-%m-%d %H:%M:%S")
        elif st_roll < 0.98:
            order_status = "CANCELLED"
            pay_status = "FAILED"
            finish_time_str = None
        else:
            order_status = "ABANDONED"
            pay_status = "SUCCESS"
            finish_time_str = (o_time + timedelta(minutes=random.randint(4, 7))).strftime("%Y-%m-%d %H:%M:%S")

        pay_method = random.choices(["WECHAT", "ALIPAY", "CASH", "CARD"], weights=[0.65, 0.25, 0.08, 0.02])[0]
        pay_time_str = (o_time + timedelta(seconds=random.randint(10, 35))).strftime("%Y-%m-%d %H:%M:%S") if pay_status == "SUCCESS" else None
        trade_no = f"{pay_method[:2]}{current_d.strftime('%Y%m%d')}{random.randint(10000000, 99999999)}" if pay_method != "CASH" and pay_status == "SUCCESS" else None
        cashier_id = 2 if random.random() < 0.85 else 1 # 主要是李娜，偶尔店长

        order_time_str = o_time.strftime("%Y-%m-%d %H:%M:%S")

        # 写入订单单头 tbl_order_header
        self.tbl_order_header.append({
            "order_id": order_id,
            "order_no": order_no,
            "business_date": date_str,
            "pickup_no": pickup_no,
            "member_id": member_id,
            "coupon_id": coupon_id,
            "discount_amount": discount_amount,
            "amount_due": amount_due,
            "amount_paid": amount_paid,
            "pay_method": pay_method,
            "pay_status": pay_status,
            "pay_time": pay_time_str,
            "trade_no": trade_no,
            "order_status": order_status,
            "order_time": order_time_str,
            "finish_time": finish_time_str,
            "cashier_id": cashier_id
        })

        # 5. 写入明细与两路反冲扣料 (只有进入制作的有效订单扣除库存)
        deduct_inventory = (order_status in ("COMPLETED", "ABANDONED"))

        # 合并本单中所有明细消耗的原料总用量: ing_id -> total_qty
        order_ingredient_usage: Dict[int, float] = {}

        for item in line_items:
            od_id = self.next_order_detail_id
            self.next_order_detail_id += 1

            self.tbl_order_detail.append({
                "order_detail_id": od_id,
                "order_id": order_id,
                "line_no": item["line_no"],
                "product_id": item["product_id"],
                "qty": item["qty"],
                "unit_price": item["unit_price"],
                "cup_spec_id": item["cup_spec_id"],
                "sugar_spec_id": item["sugar_spec_id"],
                "ice_spec_id": item["ice_spec_id"],
                "subtotal": item["subtotal"]
            })

            # 加料项子表
            for top, top_qty, top_extra in item["toppings"]:
                odt_id = self.next_od_topping_id
                self.next_od_topping_id += 1
                self.tbl_order_detail_topping.append({
                    "od_topping_id": odt_id,
                    "order_detail_id": od_id,
                    "topping_id": top["topping_id"],
                    "qty": top_qty,
                    "unit_extra_price": top_extra
                })

                # 加料扣料 (路 2: 可选增量)
                if deduct_inventory:
                    top_ing_id = top["ingredient_id"]
                    top_used = float(top["qty_per_serving"]) * top_qty
                    order_ingredient_usage[top_ing_id] = order_ingredient_usage.get(top_ing_id, 0.0) + top_used

            # 固定配方扣料 (路 1: 配方展开)
            if deduct_inventory:
                pid = item["product_id"]
                cid = item["cup_spec_id"]
                sid = item["sugar_spec_id"]
                b_qty = item["qty"]

                # 基础原料 (茶、奶、水、杯、吸管等 sugar_spec_id 为 NULL)
                base_recipes = RECIPE_BASE_INDEX.get((pid, cid), [])
                for r in base_recipes:
                    ing_id = r["ingredient_id"]
                    order_ingredient_usage[ing_id] = order_ingredient_usage.get(ing_id, 0.0) + float(r["qty"]) * b_qty

                # 糖度专属原料 (若顾客选择非 NONE)
                if sid is not None:
                    sugar_recipe = RECIPE_SUGAR_INDEX.get((pid, cid, sid))
                    if sugar_recipe:
                        ing_id = sugar_recipe["ingredient_id"]
                        order_ingredient_usage[ing_id] = order_ingredient_usage.get(ing_id, 0.0) + float(sugar_recipe["qty"]) * b_qty

        # 6. 生成库存扣减流水 SALES_USE
        if deduct_inventory:
            for ing_id, used_qty in order_ingredient_usage.items():
                used_qty = round(used_qty, 3)
                if used_qty <= 0:
                    continue

                # 严格扣减实时库存
                self.current_stock[ing_id] = round(self.current_stock[ing_id] - used_qty, 3)
                self.total_sales_use[ing_id] += used_qty

                # 断言零负库存硬约束
                assert self.current_stock[ing_id] >= -1e-6, f"严重异常: 原料 {ing_id} 出现负库存 {self.current_stock[ing_id]}!"

                # 写入流水 tbl_stock_ledger
                self.tbl_stock_ledger.append({
                    "ledger_id": self.next_ledger_id,
                    "ingredient_id": ing_id,
                    "ledger_type": "SALES_USE",
                    "qty": -used_qty,
                    "ref_type": "ORDER",
                    "purchase_order_id": None,
                    "order_id": order_id,
                    "operator_id": None, # 系统自动反冲产生
                    "ledger_time": order_time_str,
                    "remark": None
                })
                self.next_ledger_id += 1

        # 7. 会员积分累积 (1元 = 1分)
        if member_id and pay_status == "SUCCESS" and amount_paid > 0:
            earned_pts = int(amount_paid)
            if earned_pts > 0:
                self.member_points[member_id] += earned_pts
                self.tbl_points_ledger.append({
                    "point_ledger_id": self.next_point_ledger_id,
                    "member_id": member_id,
                    "point_type": "EARN",
                    "point_change": earned_pts,
                    "order_id": order_id,
                    "coupon_id": None,
                    "change_time": order_time_str
                })
                self.next_point_ledger_id += 1

    def finalize_ingredient_table(self):
        """同步最终库存量与沽清状态至原料表"""
        for ing in self.tbl_ingredient:
            ing_id = ing["ingredient_id"]
            ing["qty_on_hand"] = round(self.current_stock[ing_id], 3)
            ing["moving_avg_cost"] = round(self.moving_avg_cost[ing_id], 4)
            ing["is_sold_out"] = self.is_sold_out[ing_id]

        # 同步会员最终积分
        for m in self.tbl_member:
            mid = m["member_id"]
            m["points_balance"] = self.member_points[mid]

    def assert_reconciliation(self):
        """严格进销存台账自洽断言与平衡检验"""
        print("\n" + "=" * 92)
        print("[CHECK] 启动进销存台账绝对自洽性验证矩阵 (Invariants & Physical Balances)")
        print("=" * 92)
        print(f"{'原料编号':<8} {'原料名称':<12} {'期初库存':>10} {'采购入库(+)':>12} {'销售耗用(-)':>12} {'打烊报损(-)':>12} {'期末理论':>10} {'实际在手':>10} {'状态':^6}")
        print("-" * 92)

        reconciliation_passed = True

        for ing in self.tbl_ingredient:
            ing_id = ing["ingredient_id"]
            code = ing["ingredient_code"]
            name = ing["ingredient_name"]

            opening = self.init_opening_balance[ing_id]
            purchased = self.total_purchase_in[ing_id]
            used = self.total_sales_use[ing_id]
            lost = self.total_loss[ing_id]
            expected = round(opening + purchased - used - lost, 3)
            actual = round(ing["qty_on_hand"], 3)

            diff = abs(expected - actual)
            is_ok = (diff < 1e-4) and (actual >= 0)

            if not is_ok:
                reconciliation_passed = False

            # 打印部分代表性原料与边界原料
            if ing_id in (1, 2, 7, 8, 12, 17, 27, 31, 41, 45, 48, 54):
                status_str = "[OK]" if is_ok else "[FAIL]"
                print(f"{code:<8} {name:<12} {opening:>10.1f} {purchased:>12.1f} {used:>12.1f} {lost:>12.1f} {expected:>10.1f} {actual:>10.1f} {status_str:^6}")

        print("-" * 92)
        status_summary = "[PASS] 100% 绝对自洽闭环" if reconciliation_passed else "[FAIL] 存在账目差异"
        print(f"[SUMMARY] 校验样本覆盖: 60 种原料全量通过? -> {status_summary}")
        print("=" * 92 + "\n")

        assert reconciliation_passed, "进销存台账自洽性断言失败！"

        # 订单金额核算抽检
        for o in self.tbl_order_header[:50]:
            od_list = [d for d in self.tbl_order_detail if d["order_id"] == o["order_id"]]
            items_sum = round(sum(d["subtotal"] for d in od_list), 2)
            due = round(max(0.00, items_sum - o["discount_amount"]), 2)
            assert abs(due - o["amount_due"]) < 1e-4, f"订单 {o['order_no']} 应收金额计算不匹配!"
            assert abs(o["amount_due"] - o["amount_paid"]) < 1e-4, f"订单 {o['order_no']} 实收金额不匹配!"

        print(f"[OK] 17 张表数据仿真推演完成: 订单数 {len(self.tbl_order_header)}, 明细数 {len(self.tbl_order_detail)}, 流水数 {len(self.tbl_stock_ledger)}, 采购单数 {len(self.tbl_purchase_order)}")

        # 若开启第 8 周模式重构实物盘点未知损耗注入 (--enable-stocktake-variance)
        if self.enable_variance:
            print("\n" + "=" * 92)
            print("[STAGE 2] 第 8 周实物未知损耗与盘点差异报告 (Physical Stocktake Variance Preview)")
            print("=" * 92)
            print(f"{'原料编号':<8} {'原料名称':<12} {'账面库存(Book)':>15} {'实盘库存(Physical)':>18} {'损溢差异(Diff)':>15} {'损耗率(%)':>12}")
            print("-" * 92)
            for ing in self.tbl_ingredient:
                ing_id = ing["ingredient_id"]
                if ing_id in (1, 2, 7, 8, 12, 17, 27, 31, 41, 45, 48, 54):
                    code = ing["ingredient_code"]
                    name = ing["ingredient_name"]
                    book_qty = ing["qty_on_hand"]
                    # 模拟真实营业中的挥发、滴漏、挂壁等物理损溢 (0.5% ~ 1.5%)
                    var_rate = random.uniform(0.005, 0.015)
                    physical_qty = round(book_qty * (1.0 - var_rate), 3)
                    diff_qty = round(physical_qty - book_qty, 3)
                    print(f"{code:<8} {name:<12} {book_qty:>15.1f} {physical_qty:>18.1f} {diff_qty:>15.1f} {-var_rate*100:>11.2f}%")
            print("-" * 92)
            print("[INFO] 本差异数据预留供第 8 周 (ch7 模式重构) 新增 tbl_stocktake 盘点单与平账迁移使用！")
            print("=" * 92 + "\n")

# ==============================================================================
# 4. 数据导出 (CSV & SQL)
# ==============================================================================

def export_simulation_csv(sim: ShopSimulation, output_dir: str):
    """导出全部 17 张表到 CSV"""
    os.makedirs(output_dir, exist_ok=True)

    tables = [
        ("tbl_employee",              sim.tbl_employee),
        ("tbl_member",                sim.tbl_member),
        ("tbl_product_category",      sim.tbl_product_category),
        ("tbl_product",               sim.tbl_product),
        ("tbl_spec_option",           sim.tbl_spec_option),
        ("tbl_recipe",                sim.tbl_recipe),
        ("tbl_topping",               sim.tbl_topping),
        ("tbl_ingredient",            sim.tbl_ingredient),
        ("tbl_stock_ledger",          sim.tbl_stock_ledger),
        ("tbl_order_header",          sim.tbl_order_header),
        ("tbl_order_detail",          sim.tbl_order_detail),
        ("tbl_order_detail_topping",  sim.tbl_order_detail_topping),
        ("tbl_points_ledger",         sim.tbl_points_ledger),
        ("tbl_coupon",                sim.tbl_coupon),
        ("tbl_purchase_order",        sim.tbl_purchase_order),
        ("tbl_purchase_order_detail", sim.tbl_purchase_order_detail),
        ("tbl_supplier",              sim.tbl_supplier),
    ]

    for t_name, rows in tables:
        csv_path = os.path.join(output_dir, f"{t_name}.csv")
        if not rows:
            continue
        headers = list(rows[0].keys())
        with open(csv_path, "w", encoding="utf-8-sig", newline="\r\n") as f:
            f.write(",".join(headers) + "\n")
            for r in rows:
                line = []
                for h in headers:
                    val = r.get(h)
                    if val is None:
                        line.append("")
                    else:
                        s_val = str(val).replace('"', '""')
                        if "," in s_val or "\n" in s_val or '"' in s_val:
                            line.append(f'"{s_val}"')
                        else:
                            line.append(s_val)
                f.write(",".join(line) + "\n")

    print(f"[EXPORT] 成功导出 17 张核心表 CSV 到: {os.path.abspath(output_dir)}")

def export_simulation_sql(sim: ShopSimulation, sql_path: str):
    """导出符合 SQL Server 语法规范的种子数据 SQL 文件 (强制 UTF-8 BOM 与 Windows CRLF)"""
    os.makedirs(os.path.dirname(sql_path), exist_ok=True)

    # 拓扑排序装载顺序 (确保外键前置)
    tables_order = [
        ("tbl_employee",              sim.tbl_employee,              "employee_id"),
        ("tbl_product_category",      sim.tbl_product_category,      "category_id"),
        ("tbl_supplier",              sim.tbl_supplier,              "supplier_id"),
        ("tbl_spec_option",           sim.tbl_spec_option,           "spec_option_id"),
        ("tbl_ingredient",            sim.tbl_ingredient,            "ingredient_id"),
        ("tbl_product",               sim.tbl_product,               "product_id"),
        ("tbl_topping",               sim.tbl_topping,               "topping_id"),
        ("tbl_recipe",                sim.tbl_recipe,                "recipe_id"),
        ("tbl_member",                sim.tbl_member,                "member_id"),
        ("tbl_coupon",                sim.tbl_coupon,                "coupon_id"),
        ("tbl_purchase_order",        sim.tbl_purchase_order,        "purchase_order_id"),
        ("tbl_purchase_order_detail", sim.tbl_purchase_order_detail, "purchase_order_detail_id"),
        ("tbl_order_header",          sim.tbl_order_header,          "order_id"),
        ("tbl_order_detail",          sim.tbl_order_detail,          "order_detail_id"),
        ("tbl_order_detail_topping",  sim.tbl_order_detail_topping,  "od_topping_id"),
        ("tbl_stock_ledger",          sim.tbl_stock_ledger,          "ledger_id"),
        ("tbl_points_ledger",         sim.tbl_points_ledger,         "point_ledger_id"),
    ]

    with open(sql_path, "w", encoding="utf-8-sig", newline="\r\n") as f:
        f.write("-- =============================================================================\n")
        f.write("-- 奶茶店经营数据库 (茶颜小铺 · 单店)\n")
        f.write("-- 04-seed/seed_data.sql · 17 张核心表种子数据 (高保真业务仿真生成)\n")
        f.write(f"-- 生成日期: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')} | 仿真天数: {sim.days} 天\n")
        f.write("-- 进销存台账满足严格自洽: 期初 + 采购入库 - 销售耗用 - 打烊报损 = 期末库存\n")
        f.write("-- =============================================================================\n\n")
        f.write("USE milktea_shop;\nGO\n\n")

        for t_name, rows, identity_col in tables_order:
            if not rows:
                continue
            headers = list(rows[0].keys())
            f.write(f"-- -----------------------------------------------------------------------------\n")
            f.write(f"-- 表: {t_name} ({len(rows)} 行)\n")
            f.write(f"-- -----------------------------------------------------------------------------\n")
            f.write(f"SET IDENTITY_INSERT {t_name} ON;\nGO\n\n")

            # 分批插入 (每批 100 行)
            batch_size = 100
            for i in range(0, len(rows), batch_size):
                batch = rows[i:i + batch_size]
                f.write(f"INSERT INTO {t_name} ({', '.join(headers)})\nVALUES\n")
                row_strs = []
                for r in batch:
                    vals = []
                    for h in headers:
                        v = r.get(h)
                        if v is None:
                            vals.append("NULL")
                        elif isinstance(v, (int, float)):
                            vals.append(str(v))
                        else:
                            clean_str = str(v).replace("'", "''")
                            vals.append(f"N'{clean_str}'")
                    row_strs.append(f"  ({', '.join(vals)})")
                f.write(",\n".join(row_strs) + ";\nGO\n\n")

            f.write(f"SET IDENTITY_INSERT {t_name} OFF;\nGO\n\n")

    print(f"[EXPORT] 成功导出标准 SQL Server 种子脚本到: {os.path.abspath(sql_path)}")

# ==============================================================================
# 5. CLI 入口
# ==============================================================================

def main():
    parser = argparse.ArgumentParser(description="奶茶店经营数据库高保真业务造数引擎")
    parser.add_argument("--days", type=int, default=7, help="仿真天数 (默认 7，支持 90/365)")
    parser.add_argument("--start-date", type=str, default="2026-09-17", help="起始日期 (YYYY-MM-DD)")
    parser.add_argument("--seed", type=int, default=DEFAULT_SEED, help="随机种子 (默认 2026)")
    parser.add_argument("--output-dir", type=str, default="project/data/generated", help="CSV 输出目录")
    parser.add_argument("--export-sql", action="store_true", help="是否导出 SQL Server 种子脚本")
    parser.add_argument("--sql-output", type=str, default="project/sql/04-seed/seed_data.sql", help="SQL 脚本输出路径")
    parser.add_argument("--enable-stocktake-variance", action="store_true", help="是否注入第 8 周实物盘点未知损耗")

    args = parser.parse_args()

    print("\n[START] [TeaShop Data Generator] 启动高保真离线仿真造数引擎...")
    print(f"[CONFIG] 仿真周期: {args.start_date} 起共 {args.days} 天")
    print(f"[CONFIG] 随机种子: {args.seed} (100% 确定性复现)")
    if args.enable_stocktake_variance:
        print("[WARN] 第 8 周实物未知损耗注入: 已启用 (--enable-stocktake-variance)")

    sim = ShopSimulation(
        days=args.days,
        start_date_str=args.start_date,
        seed=args.seed,
        enable_variance=args.enable_stocktake_variance
    )

    sim.run()

    # 导出 CSV
    export_simulation_csv(sim, args.output_dir)

    # 导出 SQL
    if args.export_sql:
        export_simulation_sql(sim, args.sql_output)

    print("[DONE] 仿真造数全流程执行完毕！\n")

if __name__ == "__main__":
    main()
