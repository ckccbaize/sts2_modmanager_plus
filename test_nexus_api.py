#!/usr/bin/env python3
"""
测试 Nexus Mods API 下载链接获取
用法: python test_nexus_api.py
"""

import urllib.request
import urllib.parse
import json
import ssl
import sys

# API 配置
API_KEY = "dKi06w5oHQgcQ571jGDucCZsSXVagohX4cmquswGCXkyaSU=--uEFwBallAXeOJisR--UWbh+bZ4OX/uFE1V8NvFHw=="
BASE_URL = "https://api.nexusmods.com/v1"
GAME_DOMAIN = "slaythespire2"

# 测试参数（从 NXM URL 提取）
MOD_ID = 857
FILE_ID = 3352
KEY = "rYofNDZZlz8ngg0Bce9e5Q"
EXPIRES = 1778679341
USER_ID = 174171654


def make_request(endpoint, query_params=None):
    """发送 API 请求"""
    url = f"{BASE_URL}{endpoint}"
    if query_params:
        url += "?" + query_params

    print(f"\n请求: {url}")

    req = urllib.request.Request(url)
    req.add_header("APIKEY", API_KEY)
    req.add_header("Protocol-Version", "1.17.0")
    req.add_header("Application-Name", "STS2-ModManager")
    req.add_header("Application-Version", "1.0.0")
    req.add_header("User-Agent", "NexusApiClient/1.17.0")
    req.add_header("Accept", "application/json")

    try:
        # 创建 SSL 上下文
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE

        response = urllib.request.urlopen(req, context=ctx, timeout=30)
        data = response.read().decode('utf-8')
        print(f"响应状态: {response.status}")
        print(f"响应内容: {data[:500]}...")
        return json.loads(data)
    except urllib.error.HTTPError as e:
        print(f"HTTP 错误: {e.code} - {e.reason}")
        try:
            error_data = json.loads(e.read().decode('utf-8'))
            print(f"错误详情: {error_data}")
        except:
            print(f"错误响应: {e.read().decode('utf-8')[:200]}")
        return None
    except Exception as e:
        print(f"请求失败: {e}")
        return None


def test_get_mod_details():
    """测试获取模组详情"""
    print("\n" + "="*50)
    print("测试 1: 获取模组详情")
    print("="*50)

    endpoint = f"/games/{GAME_DOMAIN}/mods/{MOD_ID}"
    return make_request(endpoint)


def test_get_mod_files():
    """测试获取模组文件列表"""
    print("\n" + "="*50)
    print("测试 2: 获取模组文件列表")
    print("="*50)

    endpoint = f"/games/{GAME_DOMAIN}/mods/{MOD_ID}/files"
    return make_request(endpoint)


def test_get_download_link_direct():
    """测试直接获取下载链接（需要 Premium）"""
    print("\n" + "="*50)
    print("测试 3: 直接获取下载链接（无需参数）")
    print("="*50)

    endpoint = f"/games/{GAME_DOMAIN}/mods/{MOD_ID}/files/{FILE_ID}/download_link"
    return make_request(endpoint)


def test_get_download_link_with_key():
    """测试使用 key/expires/user_id 获取下载链接（非 Premium 用户）"""
    print("\n" + "="*50)
    print("测试 4: 使用 key/expires/user_id 获取下载链接")
    print("="*50)

    endpoint = f"/games/{GAME_DOMAIN}/mods/{MOD_ID}/files/{FILE_ID}/download_link"
    query_params = f"key={KEY}&expires={EXPIRES}&user_id={USER_ID}"

    print(f"\n参数:")
    print(f"  key={KEY}")
    print(f"  expires={EXPIRES}")
    print(f"  user_id={USER_ID}")

    return make_request(endpoint, query_params)


def test_validate_api_key():
    """测试验证 API Key"""
    print("\n" + "="*50)
    print("测试 0: 验证 API Key")
    print("="*50)

    endpoint = "/users/validate"
    return make_request(endpoint)


def main():
    print("Nexus Mods API 测试脚本")
    print("="*50)
    print(f"API Key: {API_KEY[:20]}...")
    print(f"游戏域名: {GAME_DOMAIN}")
    print(f"模组 ID: {MOD_ID}")
    print(f"文件 ID: {FILE_ID}")
    print()

    # 先验证 API Key
    result = test_validate_api_key()
    if result:
        print(f"\n✓ API Key 验证成功!")
        print(f"  用户名: {result.get('name', 'N/A')}")
        print(f"  用户 ID: {result.get('user_id', 'N/A')}")
        print(f"  Premium: {result.get('is_premium?', False)}")
        print(f"  Supporter: {result.get('is_supporter?', False)}")
    else:
        print(f"\n✗ API Key 验证失败!")
        print("请检查 API Key 是否正确。")

    # 测试获取模组详情
    test_get_mod_details()

    # 测试获取文件列表
    test_get_mod_files()

    # 测试直接获取下载链接
    result = test_get_download_link_direct()
    if result:
        print(f"\n✓ 直接下载链接获取成功!")
        if isinstance(result, list) and len(result) > 0:
            print(f"  第一个链接: {result[0].get('URI', 'N/A')[:100]}")
        elif isinstance(result, dict):
            print(f"  链接: {result.get('URI', 'N/A')[:100]}")
    else:
        print(f"\n✗ 直接下载链接获取失败（可能需要 Premium）")

    # 测试使用 key/expires/user_id 获取下载链接
    result = test_get_download_link_with_key()
    if result:
        print(f"\n✓ 带参数的下载链接获取成功!")
        if isinstance(result, list) and len(result) > 0:
            print(f"  第一个链接: {result[0].get('URI', 'N/A')[:100]}")
        elif isinstance(result, dict):
            print(f"  链接: {result.get('URI', 'N/A')[:100]}")
    else:
        print(f"\n✗ 带参数的下载链接获取失败")
        print("可能的原因:")
        print("  1. key/expires/user_id 已过期")
        print("  2. API Key 无效")
        print("  3. 网络问题")

    print("\n" + "="*50)
    print("测试完成!")


if __name__ == "__main__":
    main()
