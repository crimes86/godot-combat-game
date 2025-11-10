#!/usr/bin/env python3
import json
import random
import math

# Prop types with specific rules
PROP_RULES = {
    "ash_pile": {"rotate": False, "flip_h": True, "shadow": "normal"},
    "bones": {"rotate": True, "flip_h": True, "shadow": "embedded"},
    "broken_sword": {"rotate": True, "flip_h": True, "shadow": "embedded"},
    "dead_tree_1": {"rotate": False, "flip_h": True, "shadow": "normal"},  # Only straight up
    # dead_tree_2 - REMOVED (doesn't look like a tree)
    "ground_crack_1": {"rotate": True, "flip_h": True, "shadow": "inset"},  # Goes INTO ground
    "ground_crack_2": {"rotate": True, "flip_h": True, "shadow": "inset"},  # Goes INTO ground
    "rock_large": {"rotate": "limited", "flip_h": True, "shadow": "normal"},  # No small-side-down
    "rock_medium": {"rotate": False, "flip_h": True, "shadow": "normal"},  # Horizontal flip only
    "rock_small": {"rotate": False, "flip_h": True, "shadow": "normal"},  # Horizontal flip only
    "skull": {"rotate": True, "flip_h": True, "shadow": "embedded"}  # Sitting in dirt
}

# Size ranges
SIZE_RANGES = {
    "ash_pile": (0.9, 1.3),
    "bones": (0.8, 1.4),
    "broken_sword": (0.9, 1.3),
    "dead_tree_1": (0.7, 1.6),
    "ground_crack_1": (1.0, 1.5),
    "ground_crack_2": (1.0, 1.5),
    "rock_large": (1.0, 1.8),
    "rock_medium": (0.9, 1.5),
    "rock_small": (0.8, 1.4),
    "skull": (0.9, 1.3)
}

# Categorize props
ROCK_TYPES = ["rock_small", "rock_medium", "rock_large"]
TREE_TYPES = ["dead_tree_1"]  # Removed dead_tree_2
GROUND_DECOR = ["skull", "bones", "ground_crack_1", "ground_crack_2", "broken_sword", "ash_pile"]

def get_rotation_for_prop(prop_type):
    """Get rotation based on prop-specific rules"""
    rule = PROP_RULES.get(prop_type, {})
    rotate = rule.get("rotate", False)
    
    if rotate == True:
        # Full rotation
        return random.random() * 2 * math.pi
    elif rotate == "limited":
        # For rock_large: avoid small-side-down (limit to ±60 degrees)
        return random.uniform(-math.pi/3, math.pi/3)
    else:
        # No rotation (stays upright)
        return 0.0

def get_flip_for_prop(prop_type):
    """Get horizontal flip based on prop rules"""
    rule = PROP_RULES.get(prop_type, {})
    can_flip = rule.get("flip_h", True)
    return random.random() > 0.5 if can_flip else False

def get_shadow_type(prop_type):
    """Get shadow type for prop"""
    rule = PROP_RULES.get(prop_type, {})
    return rule.get("shadow", "normal")

def get_path_y_at_x(x, path_points):
    """Get interpolated Y position along the path for given X"""
    keys = sorted(path_points.keys())
    
    prev_x = keys[0]
    next_x = keys[-1]
    
    for key in keys:
        if key <= x:
            prev_x = key
        if key >= x:
            next_x = key
            break
    
    if prev_x == next_x:
        return path_points[prev_x]
    
    # Linear interpolation
    t = (x - prev_x) / (next_x - prev_x)
    return path_points[prev_x] + (path_points[next_x] - path_points[prev_x]) * t

def generate_props():
    props = []
    prop_id = 0
    
    # Path coordinates
    path_points = {
        400: 0, 800: -100, 1200: -200, 1600: -100, 2000: 50,
        2400: 150, 2800: 100, 3200: -100, 3600: -200, 4000: -100,
        4400: 100, 4800: 50, 5200: -50, 5600: 0, 6000: -50,
        6400: 50, 6800: 0, 7200: -50, 7600: 0
    }
    
    # Generate props along the world
    for x in range(600, 7400, 150):
        base_y = get_path_y_at_x(x, path_points)
        
        # Scatter props on both sides of the path
        for side in [-1, 1]:
            distance_from_path = random.uniform(200, 500) * side
            y = base_y + distance_from_path
            
            # Randomly decide what to place
            rand = random.random()
            
            if rand < 0.4:  # 40% rocks
                rock_type = random.choice(ROCK_TYPES)
                size_range = SIZE_RANGES[rock_type]
                
                props.append({
                    "id": prop_id,
                    "type": rock_type,
                    "x": x + random.uniform(-50, 50),
                    "y": y + random.uniform(-50, 50),
                    "scale": random.uniform(size_range[0], size_range[1]),
                    "rotation": get_rotation_for_prop(rock_type),
                    "flip_h": get_flip_for_prop(rock_type),
                    "z_index": -1,
                    "shadow_type": get_shadow_type(rock_type)
                })
                prop_id += 1
                
            elif rand < 0.55:  # 15% trees (reduced from 20% since we removed dead_tree_2)
                tree_type = random.choice(TREE_TYPES)
                size_range = SIZE_RANGES[tree_type]
                
                props.append({
                    "id": prop_id,
                    "type": tree_type,
                    "x": x + random.uniform(-80, 80),
                    "y": y + random.uniform(-80, 80),
                    "scale": random.uniform(size_range[0], size_range[1]),
                    "rotation": get_rotation_for_prop(tree_type),
                    "flip_h": get_flip_for_prop(tree_type),
                    "z_index": -1,
                    "shadow_type": get_shadow_type(tree_type)
                })
                prop_id += 1
                
            elif rand < 0.85:  # 30% ground decor (increased to compensate)
                decor_type = random.choice(GROUND_DECOR)
                size_range = SIZE_RANGES.get(decor_type, (0.8, 1.3))
                
                props.append({
                    "id": prop_id,
                    "type": decor_type,
                    "x": x + random.uniform(-100, 100),
                    "y": y + random.uniform(-100, 100),
                    "scale": random.uniform(size_range[0], size_range[1]),
                    "rotation": get_rotation_for_prop(decor_type),
                    "flip_h": get_flip_for_prop(decor_type),
                    "z_index": -1,
                    "shadow_type": get_shadow_type(decor_type)
                })
                prop_id += 1
    
    # Add clusters
    add_clusters(props, prop_id)
    
    return props

def add_clusters(props, start_id):
    """Add clusters of rocks and trees"""
    prop_id = start_id
    
    cluster_centers = [
        (1500, -400),
        (2800, 300),
        (4200, -300),
        (5500, 200),
        (6800, -200)
    ]
    
    for center_x, center_y in cluster_centers:
        # Add 5-8 rocks
        num_rocks = random.randint(5, 8)
        for i in range(num_rocks):
            rock_type = random.choice(ROCK_TYPES)
            size_range = SIZE_RANGES[rock_type]
            offset_x = random.uniform(-150, 150)
            offset_y = random.uniform(-150, 150)
            
            props.append({
                "id": prop_id,
                "type": rock_type,
                "x": center_x + offset_x,
                "y": center_y + offset_y,
                "scale": random.uniform(size_range[0], size_range[1]),
                "rotation": get_rotation_for_prop(rock_type),
                "flip_h": get_flip_for_prop(rock_type),
                "z_index": -1,
                "shadow_type": get_shadow_type(rock_type)
            })
            prop_id += 1
        
        # Add 2-3 trees
        num_trees = random.randint(2, 3)
        for i in range(num_trees):
            tree_type = random.choice(TREE_TYPES)
            size_range = SIZE_RANGES[tree_type]
            offset_x = random.uniform(-200, 200)
            offset_y = random.uniform(-200, 200)
            
            props.append({
                "id": prop_id,
                "type": tree_type,
                "x": center_x + offset_x,
                "y": center_y + offset_y,
                "scale": random.uniform(size_range[0], size_range[1]),
                "rotation": get_rotation_for_prop(tree_type),
                "flip_h": get_flip_for_prop(tree_type),
                "z_index": -1,
                "shadow_type": get_shadow_type(tree_type)
            })
            prop_id += 1
    
    return prop_id

if __name__ == "__main__":
    print("🎨 Generating props with specific rules per type...")
    print("")
    print("Prop Rules:")
    for prop_type, rules in PROP_RULES.items():
        rotate_str = "YES" if rules["rotate"] == True else ("LIMITED" if rules["rotate"] == "limited" else "NO")
        print(f"  {prop_type:20} Rotate: {rotate_str:8} Flip: {'YES' if rules['flip_h'] else 'NO':3} Shadow: {rules['shadow']}")
    print("")
    
    props = generate_props()
    
    data = {"ScatteredProps": props}
    
    with open("prop_placements.json", "w") as f:
        json.dump(data, f, indent=2)
    
    print(f"✅ Generated {len(props)} props with specific rules per type!")
    print(f"💾 Saved to prop_placements.json")
