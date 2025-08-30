import cv2
import time
import keyboard
import numpy as np
from PIL import Image, ImageGrab
from collections import deque, namedtuple

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

def is_in(img, subimg):
    """return if 'subimg' is in 'img'"""
    subimg1 = cv2.cvtColor(np.array(subimg), cv2.COLOR_BGR2GRAY)
    res = cv2.matchTemplate(img, subimg1, cv2.TM_CCOEFF_NORMED)
    threshold = 0.65
    loc = np.where(res >= threshold)
    for pt in zip(*loc[::-1]):
        return True
    return False

def find_shortest_solution(target_coordinates):
    Point = namedtuple('Point', ('x', 'y'))
    ReverseLinkedNode = namedtuple("ReverseLinkedNode", ('value', 'prev_node', 'idx'))
    rows, cols = 4, 2
    directions = [(0, 1, 's'), (1, 0, 'd'), (0, -1, 'w'), (-1, 0, 'a')]

    target_coordinates = [p if isinstance(p, Point) else Point(*p) for p in target_coordinates]
    target_mask = 0
    for target in target_coordinates:
        target_mask |= 1 << ((target.y * cols) + target.x)

    current_pos = Point(0, 0)
    visited_mask = 1
    path_head: ReverseLinkedNode = ReverseLinkedNode(None, None, -1)
    if current_pos in target_coordinates:
        path_head = ReverseLinkedNode('return', path_head, 0)
    queue = deque([(current_pos, visited_mask, path_head)])

    while len(queue) > 0:
        current_pos, visited_mask, path_head = queue.popleft()

        if visited_mask & target_mask == target_mask:
            output_list = [None] * (path_head.idx + 1)
            while path_head.idx >= 0:
                output_list[path_head.idx] = path_head.value
                path_head = path_head.prev_node
            return output_list + ['tab']

        for delta_x, delta_y, key in directions:
            new_x, new_y = current_pos.x + delta_x, current_pos.y + delta_y
            if new_x == -1:
                new_x, new_y = cols-1, new_y-1
            elif new_x == cols:
                new_x, new_y = 0, new_y+1
            new_y = new_y % rows

            next_pos = Point(new_x, new_y)
            pos_mask = 1 << ((next_pos.y * cols) + next_pos.x)
            next_visited_mask = visited_mask | pos_mask
            if visited_mask == next_visited_mask:
                continue

            next_path_head = ReverseLinkedNode(key, path_head, path_head.idx+1)
            if target_mask & pos_mask != 0:
                next_path_head = ReverseLinkedNode('return', next_path_head, next_path_head.idx+1)
            queue.append((next_pos, next_visited_mask, next_path_head))

    raise Exception('No solution found')

def main(bbox):
    print('[*] Casino Fingerprint')
    
    # 현재 윈도우 크기 계산
    window_width = bbox[2] - bbox[0]
    window_height = bbox[3] - bbox[1]
    
    # 현재 해상도에 맞는 좌표들 가져오기
    tofind, parts = get_scaled_coordinates(window_width, window_height)
    
    im = ImageGrab.grab(bbox)
    im = im.resize((window_width, window_height))
    sub0_ = im.crop(tofind)
    sub0 = cv2.cvtColor(np.array(sub0_.resize((round(sub0_.size[0] * 0.77), round(sub0_.size[1] * 0.77)))), cv2.COLOR_BGR2GRAY)

    togo = [part[1] for part in parts if is_in(sub0, im.crop(part[0]))]

    sub0_.close()
    im.close()

    moves = find_shortest_solution(togo)

    print('-', moves)
    for key in moves:
        keyboard.press_and_release(key)
        time.sleep(0.025)
    print('[*] END')
    print('=============================================')