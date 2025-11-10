#!/usr/bin/env python3
import json
import random
import math

# Prop categories
ROCK_TYPES = ["rock_small", "rock_medium", "rock_large"]
TREE_TYPES = ["dead_tree_1"]  # Only use dead_tree_1 (dead_tree_2 removed)
GROUND_DECOR = ["skull", "bones", "ground_crack_1", "ground_crack_2", "broken_sword", "ash_pile"]

# Size ranges for each type
SIZE_RANGES = {
    "rock_small": (0.8, 1.4),
    "rock_medium": (0.9, 1.5),
    "rock_large": (1.0, 1.8),
    "dead_tree_1": (0.7, 1.6),
}

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
            
            rand = random.random()
            
            if rand < 0.4:  # 40% chance for rocks
                rock_type = random.choice(ROCK_TYPES)
                size_range = SIZE_RANGES[rock_type]
                scale = random.uniform(size_range[0], size_range[1])
                
                # Rock rotation rules:
                if rock_type == "rock_large":
                    # Can rotate, but limit to prevent small-side-down look
                    rotation = random.uniform(-math.pi/3, math.pi/3)  # ±60 degrees
                elif rock_type in ["rock_medium", "rock_small"]:
                    # No rotation (horizontal flip only handled by flip_h)
                    rotation = 0.0
                else:
                    rotation = 0.0
                
                props.append({
                    "id": prop_id,
                    "type": rock_type,
                    "x": x + random.uniform(-50, 50),
                    "y": y + random.uniform(-50, 50),
                    "scale": scale,
                    "rotation": rotation,
                    "flip_h": random.random() > 0.5,
                    "z_index": -1
                })
                prop_id += 1
                
            elif rand < 0.55:  # 15% chance for trees (reduced)
                tree_type = "dead_tree_1"  # Only use tree 1
                size_range = SIZE_RANGES[tree_type]
                scale = random.uniform(size_range[0], size_range[1])
                
                # Trees: NO rotation (always straight up)
                rotation = 0.0
                
                props.append({
                    "id": prop_id,
                    "type": tree_type,
                    "x": x + random.uniform(-80, 80),
                    "y": y + random.uniform(-80, 80),
                    "scale": scale,
                    "rotation": rotation,
                    "flip_h": random.random() > 0.5,
                    "z_index": -1
                })
                prop_id += 1
                
            elif rand < 0.85:  # 30% chance for ground decor
                decor_type = random.choice(GROUND_DECOR)
                
                # Ground decor rotation rules:
                if decor_type == "ash_pile":
                    rotation = 0.0  # No rotation
                elif decor_type in ["bones", "broken_sword", "skull"]:
                    # Can rotate any direction (lying on ground)
                    rotation = random.random() * 2 * math.pi
                elif decor_type in ["ground_crack_1", "ground_crack_2"]:
                    # Any direction (cracks in ground)
                    rotation = random.random() * 2 * math.pi
                else:
                    rotation = 0.0
                
                props.append({
                    "id": prop_id,
                    "type": decor_type,
                    "x": x + random.uniform(-100, 100),
                    "y": y + random.uniform(-100, 100),
                    "scale": random.uniform(0.8, 1.3),
                    "rotation": rotation,
                    "flip_h": random.random() > 0.5,
                    "z_index": -1
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
            
            # Rock rotation rules in clusters
            if rock_type == "rock_large":
                rotation = random.uniform(-math.pi/3, math.pi/3)
            else:
                rotation = 0.0
            
            props.append({
                "id": prop_id,
                "type": rock_type,
                "x": center_x + offset_x,
                "y": center_y + offset_y,
                "scale": random.uniform(size_range[0], size_range[1]),
                "rotation": rotation,
                "flip_h": random.random() > 0.5,
                "z_index": -1
            })
            prop_id += 1
        
        # Add 2-3 trees (only tree 1)
        num_trees = random.randint(2, 3)
        for i in range(num_trees):
            tree_type = "dead_tree_1"
            size_range = SIZE_RANGES[tree_type]
            offset_x = random.uniform(-200, 200)
            offset_y = random.uniform(-200, 200)
            
            # Trees: NO rotation
            props.append({
                "id": prop_id,
                "type": tree_type,
                "x": center_x + offset_x,
                "y": center_y + offset_y,
                "scale": random.uniform(size_range[0], size_range[1]),
                "rotation": 0.0,  # Always straight up
                "flip_h": random.random() > 0.5,
                "z_index": -1
            })
            prop_id += 1
    
    return prop_id

if __name__ == "__main__":
    print("🎨 Generating props with specific rotation rules...")
    props = generate_props()
    
    data = {"ScatteredProps": props}
    
    with open("prop_placements.json", "w") as f:
        json.dump(data, f, indent=2)
    
    print(f"✅ Generated {len(props)} props!")
    print(f"💾 Saved to prop_placements.json")
    print("")
    print("Rotation rules applied:")
    print("  - Trees (dead_tree_1): Always straight up (0°)")
    print("  - Rock large: ±60° max")
    print("  - Rock medium/small: No rotation")
    print("  - Skull/bones/sword: Any angle (lying on ground)")
    print("  - Cracks: Any angle")
    print("  - Ash: No rotation")
