import cv2
import time
import keyboard
import numpy as np
from PIL import Image, ImageGrab

# 기준 해상도 (1920x1080)
BASE_WIDTH = 1920
BASE_HEIGHT = 1080

# 기준 해상도 좌표들
BASE_TOFIND = (950, 155, 1335, 685)
BASE_PARTS = [[(482, 279, 584, 381), (0, 0)],
              [(627, 279, 729, 381), (1, 0)],
              [(482, 423, 584, 525), (0, 1)],
              [(627, 423, 729, 525), (1, 1)],
              [(482, 566, 584, 668), (0, 2)],
              [(627, 566, 729, 668), (1, 2)],
              [(482, 711, 584, 813), (0, 3)],
              [(627, 711, 729, 813), (1, 3)]]

def scale_coordinates(coords, scale_x, scale_y):
    """좌표를 현재 해상도에 맞게 스케일링"""
    if isinstance(coords, tuple) and len(coords) == 4:
        return (int(coords[0] * scale_x), int(coords[1] * scale_y), 
                int(coords[2] * scale_x), int(coords[3] * scale_y))
    return coords

def get_scaled_coordinates(target_width, target_height):
    """현재 해상도에 맞는 좌표들 반환"""
    scale_x = target_width / BASE_WIDTH
    scale_y = target_height / BASE_HEIGHT
    
    scaled_tofind = scale_coordinates(BASE_TOFIND, scale_x, scale_y)
    scaled_parts = []
    
    for part_coords, grid_pos in BASE_PARTS:
        scaled_coords = scale_coordinates(part_coords, scale_x, scale_y)
        scaled_parts.append([scaled_coords, grid_pos])
    
    return scaled_tofind, scaled_parts

def find_matching_parts(target_img, parts_imgs, threshold=0.5):
    """템플릿 매칭으로 일치하는 부분 찾기 - 개선된 버전"""
    matching_positions = []
    
    # 타겟 이미지를 여러 크기로 리사이즈해서 시도
    scales = [0.70, 0.75, 0.77, 0.80, 0.85]
    
    for scale in scales:
        resized_target = cv2.resize(target_img, 
                                   (int(target_img.shape[1] * scale), 
                                    int(target_img.shape[0] * scale)))
        
        for idx, (part_img, grid_pos) in enumerate(parts_imgs):
            # 히스토그램 균등화로 대비 개선
            part_img_eq = cv2.equalizeHist(part_img)
            resized_target_eq = cv2.equalizeHist(resized_target)
            
            # 템플릿 매칭
            result = cv2.matchTemplate(resized_target_eq, part_img_eq, cv2.TM_CCOEFF_NORMED)
            min_val, max_val, min_loc, max_loc = cv2.minMaxLoc(result)
            
            if max_val > threshold:
                if grid_pos not in matching_positions:
                    matching_positions.append(grid_pos)
                    print(f"[+] Found match at position {grid_pos} with confidence {max_val:.2f}")
        
        # 4개를 찾으면 바로 리턴
        if len(matching_positions) >= 4:
            break
    
    return matching_positions[:4]  # 최대 4개까지만

def simple_path_finder(targets):
    """간단한 경로 찾기 - 순차적으로 방문"""
    if not targets:
        return []
    
    moves = []
    current_pos = (0, 0)
    
    # 대상들을 순서대로 방문
    for target in targets:
        # 현재 위치에서 목표까지 이동
        x_diff = target[0] - current_pos[0]
        y_diff = target[1] - current_pos[1]
        
        # 수평 이동
        if x_diff > 0:
            moves.extend(['d'] * x_diff)
        elif x_diff < 0:
            moves.extend(['a'] * abs(x_diff))
        
        # 수직 이동
        if y_diff > 0:
            moves.extend(['s'] * y_diff)
        elif y_diff < 0:
            moves.extend(['w'] * abs(y_diff))
        
        # 선택
        moves.append('return')
        current_pos = target
    
    # 완료
    moves.append('tab')
    return moves

def main(bbox):
    print('[*] Casino Fingerprint Scanner - Fixed Version')
    
    try:
        # 현재 윈도우 크기 계산
        window_width = bbox[2] - bbox[0]
        window_height = bbox[3] - bbox[1]
        
        # 스크린샷 캡처
        im = ImageGrab.grab(bbox)
        
        # 해상도에 맞게 좌표 스케일링
        tofind, parts = get_scaled_coordinates(window_width, window_height)
        
        # 타겟 지문 이미지 추출
        target_fingerprint = im.crop(tofind)
        target_gray = cv2.cvtColor(np.array(target_fingerprint), cv2.COLOR_RGB2GRAY)
        
        # 각 부분 이미지와 위치 준비
        parts_with_imgs = []
        for part_coords, grid_pos in parts:
            part_img = im.crop(part_coords)
            part_gray = cv2.cvtColor(np.array(part_img), cv2.COLOR_RGB2GRAY)
            parts_with_imgs.append((part_gray, grid_pos))
        
        # 매칭되는 부분 찾기
        matching_positions = find_matching_parts(target_gray, parts_with_imgs)
        
        print(f'[*] Found {len(matching_positions)} matching fingerprints')
        
        if len(matching_positions) < 4:
            print(f'[!] Warning: Only found {len(matching_positions)} matches, expected 4')
            # 디버깅을 위해 이미지 저장
            target_fingerprint.save('debug_target.png')
            print('[!] Target fingerprint saved as debug_target.png for debugging')
        
        # 경로 생성
        moves = simple_path_finder(matching_positions)
        
        print(f'[*] Path: {moves}')
        
        # 키 입력 실행
        for key in moves:
            keyboard.press_and_release(key)
            if key == 'return':
                time.sleep(0.5)  # 선택 후 대기
            elif key == 'tab':
                time.sleep(0.1)  # 완료 후 대기
            else:
                time.sleep(0.025)  # 이동 딜레이
        
        print('[*] Fingerprint scan completed!')
        
    except Exception as e:
        print(f'[!] Error: {e}')
    
    finally:
        print('=' * 45)